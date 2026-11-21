package web_test

import (
	"bufio"
	"context"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"

	"znile/internal/live"
	"znile/internal/web"
)

// served runs h on a real loopback listener for the test and returns its address.
func served(t *testing.T, h *web.Handler) string {
	t.Helper()
	ln, err := web.Listen(0)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { // owner: the test; ends when the test cancels ctx
		defer close(done)
		h.Serve(ctx, ln)
	}()
	t.Cleanup(func() { cancel(); <-done })
	return ln.Addr().String()
}

func newHandler() *web.Handler { return &web.Handler{Core: live.New(live.Config{})} }

func rawGet(t *testing.T, addr, path string) (net.Conn, *bufio.Reader) {
	t.Helper()
	c, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	io.WriteString(c, "GET "+path+" HTTP/1.1\r\nHost: "+addr+"\r\n\r\n")
	return c, bufio.NewReader(c)
}

func TestIdleKeepAliveConnectionsClose(t *testing.T) {
	h := newHandler()
	h.IdleTimeout = 150 * time.Millisecond
	c, br := rawGet(t, served(t, h), "/api/state")
	resp, err := http.ReadResponse(br, nil)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, resp.Body)
	c.SetReadDeadline(time.Now().Add(3 * time.Second))
	if _, err := br.ReadByte(); err != io.EOF {
		t.Fatalf("an idle connection stays open: %v", err)
	}
}

func TestHeaderSizeIsCapped(t *testing.T) {
	addr := served(t, newHandler())
	c, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	io.WriteString(c, "GET /api/state HTTP/1.1\r\nHost: "+addr+"\r\nX-Big: "+strings.Repeat("a", 20<<10)+"\r\n\r\n")
	c.SetReadDeadline(time.Now().Add(3 * time.Second))
	resp, err := http.ReadResponse(bufio.NewReader(c), nil)
	if err != nil || resp.StatusCode != http.StatusRequestHeaderFieldsTooLarge {
		t.Fatalf("a 20 KiB header: %v %v", resp, err)
	}
}

func TestConnectionCap(t *testing.T) {
	h := newHandler()
	h.MaxConns = 2
	addr := served(t, h)
	var held []net.Conn
	for i := 0; i < 2; i++ {
		c, br := rawGet(t, addr, "/api/state")
		resp, err := http.ReadResponse(br, nil)
		if err != nil {
			t.Fatal(err)
		}
		io.Copy(io.Discard, resp.Body)
		held = append(held, c)
	}
	third, br := rawGet(t, addr, "/api/state")
	third.SetReadDeadline(time.Now().Add(400 * time.Millisecond))
	if _, err := br.ReadByte(); err == nil {
		t.Fatal("a third connection was served beyond the cap")
	}
	held[0].Close()
	third.SetReadDeadline(time.Now().Add(5 * time.Second))
	if resp, err := http.ReadResponse(br, nil); err != nil || resp.StatusCode != 200 {
		t.Fatalf("after a slot freed: %v %v", resp, err)
	}
}

func TestStreamCap(t *testing.T) {
	h := newHandler()
	h.MaxStreams = 2
	addr := served(t, h)
	open := func() *http.Response {
		req, _ := http.NewRequest("GET", "http://"+addr+"/api/events", nil)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		return resp
	}
	a, b := open(), open()
	defer b.Body.Close()
	third := open()
	body, _ := io.ReadAll(third.Body)
	third.Body.Close()
	if third.StatusCode != http.StatusServiceUnavailable || !strings.Contains(string(body), "limit of 2") {
		t.Fatalf("third stream: %d %q", third.StatusCode, body)
	}
	a.Body.Close()
	deadline := time.Now().Add(3 * time.Second)
	for h.Open() > 1 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	fourth := open()
	defer fourth.Body.Close()
	if fourth.StatusCode != 200 {
		t.Fatalf("after a stream closed: %d", fourth.StatusCode)
	}
}

// A reader that stops reading is dropped at the write deadline, and the open count falls back to zero.
func TestStalledStreamReaderIsDropped(t *testing.T) {
	h := newHandler()
	h.WriteTimeout = 300 * time.Millisecond
	addr := served(t, h)
	tcp, err := net.Dial("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	defer tcp.Close()
	tcp.(*net.TCPConn).SetReadBuffer(1024)
	io.WriteString(tcp, "GET /api/events HTTP/1.1\r\nHost: "+addr+"\r\n\r\n")
	deadline := time.Now().Add(3 * time.Second)
	for h.Open() < 1 && time.Now().Before(deadline) {
		time.Sleep(5 * time.Millisecond)
	}
	if h.Open() != 1 {
		t.Fatal("the stream did not open")
	}
	pad := strings.Repeat("x", 480)
	for i := 0; i < 8000 && h.Open() > 0; i++ {
		h.Core.Do(live.Request{Op: "emit", Proto: live.Proto, Kind: "filler", Outcome: pad})
	}
	deadline = time.Now().Add(5 * time.Second)
	for h.Open() > 0 && time.Now().Before(deadline) {
		time.Sleep(20 * time.Millisecond)
	}
	if h.Open() != 0 {
		t.Fatalf("a stalled reader still holds %d request(s)", h.Open())
	}
}
