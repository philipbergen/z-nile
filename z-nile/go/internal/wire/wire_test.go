package wire_test

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"syscall"
	"testing"
	"time"

	"znile/internal/live"
	"znile/internal/wire"
)

const stateDir = "/state/for/the/test"

type harness struct {
	t      *testing.T
	core   *live.Core
	srv    *wire.Server
	sock   string
	cancel context.CancelFunc
	done   chan struct{}
}

func shortDir(t *testing.T) string {
	t.Helper()
	d, err := os.MkdirTemp("", "zw")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(d) })
	return d
}

// start serves a Core on a socket in a short temp dir; every goroutine it starts ends before the test does.
func start(t *testing.T, wrap func(net.Listener) net.Listener) *harness {
	t.Helper()
	h := &harness{t: t, core: live.New(live.Config{Host: "h"}), sock: filepath.Join(shortDir(t), "s.sock")}
	var ln net.Listener
	ln, err := net.Listen("unix", h.sock)
	if err != nil {
		t.Fatal(err)
	}
	if wrap != nil {
		ln = wrap(ln)
	}
	ctx, cancel := context.WithCancel(context.Background())
	h.cancel = cancel
	h.srv = &wire.Server{Core: h.core, Dir: stateDir, Shutdown: cancel, PID: os.Getpid()}
	h.done = make(chan struct{})
	go func() { h.srv.Serve(ctx, ln); close(h.done) }()
	t.Cleanup(func() {
		cancel()
		select {
		case <-h.done:
		case <-time.After(10 * time.Second):
			t.Error("Serve did not return")
		}
	})
	return h
}

func (h *harness) req(r live.Request) live.Request {
	r.Dir, r.Proto = stateDir, live.Proto
	return r
}

func (h *harness) call(r live.Request) (wire.Result, error) {
	c, err := wire.Dial(h.sock)
	if err != nil {
		return wire.Result{}, err
	}
	return wire.Call(c, h.req(r), 5*time.Second, nil)
}

func settle(t *testing.T, what string, ok func() bool) {
	t.Helper()
	for i := 0; i < 300; i++ {
		if ok() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("never happened: %s", what)
}

// F3: a follow is streamed line by line, and a reader that goes away leaves no connection and no goroutine behind.
func TestFollowStreamsAndHangupLeaksNothing(t *testing.T) {
	h := start(t, nil)
	time.Sleep(100 * time.Millisecond) // let the server's own goroutines start
	base := runtime.NumGoroutine()
	c, err := wire.Dial(h.sock)
	if err != nil {
		t.Fatal(err)
	}
	b, _ := json.Marshal(h.req(live.Request{Op: "events", Follow: true, Timeout: 30}))
	c.Write(append(b, '\n'))
	settle(t, "the follow is connected", func() bool { return h.srv.Open() == 1 })
	h.call(live.Request{Op: "poke", Reason: "one"})
	line, err := bufio.NewReader(c).ReadString('\n')
	if err != nil || !strings.Contains(line, `"reason":"one"`) {
		t.Fatalf("%q %v", line, err)
	}
	c.Close() // the reader goes away
	settle(t, "the connection is gone", func() bool { return h.srv.Open() == 0 })
	settle(t, "the goroutines are gone", func() bool { return runtime.NumGoroutine() <= base })
}

type flaky struct {
	net.Listener
	left atomic.Int32
}

func (f *flaky) Accept() (net.Conn, error) {
	if f.left.Add(-1) >= 0 {
		return nil, &net.OpError{Op: "accept", Err: syscall.EMFILE}
	}
	return f.Listener.Accept()
}

// F13: a temporary Accept error is retried and does not end the daemon.
func TestAcceptRetriesTemporaryErrors(t *testing.T) {
	h := start(t, func(ln net.Listener) net.Listener {
		f := &flaky{Listener: ln}
		f.left.Store(3)
		return f
	})
	res, err := h.call(live.Request{Op: "status"})
	if err != nil || !res.Reply.OK() {
		t.Fatalf("%v %v", res.Reply, err)
	}
}

// F13: stopping closes the listener and cancels the waiters, which are told; Serve returns.
func TestShutdownCancelsWaits(t *testing.T) {
	h := start(t, nil)
	h.call(live.Request{Op: "register", Worker: "w", CLI: "t", PID: os.Getpid()})
	got := make(chan live.Reply, 1)
	go func() {
		res, _ := h.call(live.Request{Op: "wait", Worker: "w", Timeout: 60})
		got <- res.Reply
	}()
	settle(t, "the wait is connected", func() bool { return h.srv.Open() == 1 })
	h.cancel()
	select {
	case rep := <-got:
		if rep.Refused() != "closed" {
			t.Fatalf("%v", rep)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the wait was not cancelled")
	}
	select {
	case <-h.done:
	case <-time.After(5 * time.Second):
		t.Fatal("Serve did not return")
	}
	if _, err := net.Dial("unix", h.sock); err == nil {
		t.Fatal("still listening")
	}
}

// F16: a request over the size limit gets a usage reply before the connection closes.
func TestOversizeRequestAnswered(t *testing.T) {
	h := start(t, nil)
	c, err := net.Dial("unix", h.sock)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	go func() { c.Write([]byte(strings.Repeat("x", 2<<20))) }()
	c.SetReadDeadline(time.Now().Add(5 * time.Second))
	line, err := bufio.NewReader(c).ReadString('\n')
	if err != nil || !strings.Contains(line, `"refused":"usage"`) {
		t.Fatalf("%q %v", line, err)
	}
}

// F16: the dir and proto refusals carry seq, and events against another repository's daemon names the dir.
func TestRefusalsCarrySeqAndNameTheDir(t *testing.T) {
	h := start(t, nil)
	h.call(live.Request{Op: "poke"})
	for _, r := range []live.Request{{Op: "status", Dir: "/elsewhere", Proto: live.Proto}, {Op: "events", Dir: "/elsewhere", Proto: live.Proto, Follow: true},
		{Op: "status", Dir: stateDir, Proto: 7}} {
		c, err := wire.Dial(h.sock)
		if err != nil {
			t.Fatal(err)
		}
		res, err := wire.Call(c, r, 5*time.Second, nil)
		if err != nil {
			t.Fatalf("%s: %v", r.Op, err)
		}
		if w := res.Reply.Refused(); w != "dir" && w != "proto" || res.Reply["seq"] != float64(1) {
			t.Fatalf("%s: %v", r.Op, res.Reply)
		}
	}
	res, _ := h.call(live.Request{Op: "shutdown"})
	if res.Reply["seq"] != float64(1) {
		t.Fatalf("shutdown reply %v", res.Reply)
	}
}

// F13: a refused connection while the socket file exists is retried inside the budget.
func TestDialRetriesWhileSocketFileExists(t *testing.T) {
	sock := filepath.Join(shortDir(t), "s.sock")
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: sock, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	ln.SetUnlinkOnClose(false)
	ln.Close() // the file stays, nobody listens: connection refused
	if _, err := os.Stat(sock); err != nil {
		t.Fatal(err)
	}
	back := make(chan net.Listener, 1)
	go func() {
		time.Sleep(300 * time.Millisecond)
		os.Remove(sock)
		l, err := net.Listen("unix", sock)
		if err != nil {
			back <- nil
			return
		}
		back <- l
	}()
	c, err := wire.Dial(sock)
	l := <-back
	if l != nil {
		defer l.Close()
	}
	if err != nil {
		t.Fatalf("the dial gave up: %v", err)
	}
	c.Close()
	// and a missing file is not retried
	t0 := time.Now()
	if _, err := wire.Dial(sock + ".none"); !errors.Is(err, os.ErrNotExist) || time.Since(t0) > time.Second {
		t.Fatalf("%v after %s", err, time.Since(t0))
	}
}
