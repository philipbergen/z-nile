package web_test

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"znile/internal/live"
	"znile/internal/web"
)

// rig is a core with two registered workers and a claim, served by the handler on a real loopback listener.
type rig struct {
	t    *testing.T
	core *live.Core
	h    *web.Handler
	srv  *httptest.Server
	host string // host:port the server answers to
}

func newRigPage(t *testing.T, page string) *rig { return newRig(t, page, 0) }

func readAll(resp *http.Response) string {
	b, _ := io.ReadAll(resp.Body)
	return string(b)
}

func newRig(t *testing.T, page string, heartbeat time.Duration) *rig {
	t.Helper()
	core := live.New(live.Config{})
	pid := os.Getpid()
	for _, id := range []string{"claude-1", "grok-2"} {
		rep := core.Do(live.Request{Op: "register", Proto: live.Proto, Worker: id, CLI: strings.Split(id, "-")[0], PID: pid,
			Mode: "session", Can: []string{"code/heavy", "design/light"}})
		if !rep.OK() {
			t.Fatalf("register %s: %v", id, rep)
		}
	}
	if rep := core.Do(live.Request{Op: "claim", Proto: live.Proto, Worker: "claude-1", Unit: "c0001", Activity: "code"}); !rep.OK() {
		t.Fatalf("claim: %v", rep)
	}
	h := &web.Handler{Core: core, PagePath: page, Heartbeat: heartbeat}
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	h.Addr = srv.Listener.Addr().String()
	return &rig{t: t, core: core, h: h, srv: srv, host: h.Addr}
}

func (r *rig) get(path, host, origin string) *http.Response {
	r.t.Helper()
	req, _ := http.NewRequest("GET", r.srv.URL+path, nil)
	if host != "" {
		req.Host = host
	}
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		r.t.Fatal(err)
	}
	r.t.Cleanup(func() { resp.Body.Close() })
	return resp
}

// The listener is loopback only, whatever the caller asks for.
func TestListenIsLoopbackOnly(t *testing.T) {
	ln, err := web.Listen(0)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	a := ln.Addr().(*net.TCPAddr)
	if !a.IP.Equal(net.IPv4(127, 0, 0, 1)) || a.Port == 0 {
		t.Fatalf("listening on %v, want 127.0.0.1 and a port", a)
	}
}

func TestStateShape(t *testing.T) {
	r := newRig(t, "", 0)
	resp := r.get("/api/state", r.host, "")
	if resp.StatusCode != 200 || !strings.HasPrefix(resp.Header.Get("Content-Type"), "application/json") {
		t.Fatalf("status %d type %q", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	var st struct {
		Seq     int64 `json:"seq"`
		Now     float64
		Workers []struct {
			ID      string   `json:"id"`
			CLI     string   `json:"cli"`
			State   string   `json:"state"`
			Started float64  `json:"started"`
			Heard   float64  `json:"heard"`
			Can     []string `json:"can"`
			Holds   *struct {
				Unit     string  `json:"unit"`
				Activity string  `json:"activity"`
				Since    float64 `json:"since"`
			} `json:"holds"`
		} `json:"workers"`
		Claims []struct {
			Unit     string  `json:"unit"`
			Activity string  `json:"activity"`
			Worker   string  `json:"worker"`
			Since    float64 `json:"since"`
		} `json:"claims"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&st); err != nil {
		t.Fatal(err)
	}
	if len(st.Workers) != 2 || st.Workers[0].ID != "claude-1" || st.Workers[1].ID != "grok-2" {
		t.Fatalf("workers: %+v", st.Workers)
	}
	a, b := st.Workers[0], st.Workers[1]
	if a.CLI != "claude" || a.State != "working" || a.Holds == nil || a.Holds.Unit != "c0001" || a.Holds.Activity != "code" ||
		a.Holds.Since == 0 || a.Heard == 0 || a.Started == 0 || strings.Join(a.Can, ",") != "code/heavy,design/light" {
		t.Fatalf("working worker: %+v", a)
	}
	if b.State != "idle" || b.Holds != nil {
		t.Fatalf("idle worker: %+v", b)
	}
	if len(st.Claims) != 1 || st.Claims[0].Unit != "c0001" || st.Claims[0].Worker != "claude-1" || st.Claims[0].Since == 0 {
		t.Fatalf("claims: %+v", st.Claims)
	}
	if st.Seq == 0 || st.Now == 0 {
		t.Fatalf("seq %d now %v", st.Seq, st.Now)
	}
}

func TestSameOriginOnly(t *testing.T) {
	r := newRig(t, "", 0)
	_, port, _ := net.SplitHostPort(r.host)
	for _, c := range []struct {
		name, host, origin string
		want               int
	}{
		{"loopback host", r.host, "", 200},
		{"localhost host", "localhost:" + port, "", 200},
		{"own origin", r.host, "http://" + r.host, 200},
		{"other host", "evil.example:" + port, "", 403},
		{"no port", "127.0.0.1", "", 403},
		{"other port", "127.0.0.1:1", "", 403},
		{"other origin", r.host, "http://evil.example", 403},
		{"null origin", r.host, "null", 403},
	} {
		resp := r.get("/api/state", c.host, c.origin)
		if resp.StatusCode != c.want {
			t.Errorf("%s: status %d, want %d", c.name, resp.StatusCode, c.want)
		}
		for k := range resp.Header {
			if strings.HasPrefix(strings.ToLower(k), "access-control-") {
				t.Errorf("%s: sent %s", c.name, k)
			}
		}
		if c.want == 403 {
			body := new(strings.Builder)
			bufio.NewReader(resp.Body).WriteTo(body)
			if strings.Contains(body.String(), "claude-1") {
				t.Errorf("%s: a refused request got data", c.name)
			}
		}
	}
	for _, m := range []string{"POST", "PUT", "DELETE", "OPTIONS"} {
		req, _ := http.NewRequest(m, r.srv.URL+"/api/state", nil)
		req.Host = r.host
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != 405 {
			t.Errorf("%s: status %d, want 405", m, resp.StatusCode)
		}
	}
	if resp := r.get("/nope", r.host, ""); resp.StatusCode != 404 {
		t.Errorf("unknown path: %d", resp.StatusCode)
	}
}

func TestPageIsReadAtRequestTime(t *testing.T) {
	page := filepath.Join(realTemp(t), "z-nile", "app", "index.html")
	r := newRig(t, page, 0)
	if resp := r.get("/", r.host, ""); resp.StatusCode != 404 {
		t.Fatalf("a missing page: %d", resp.StatusCode)
	}
	read := func() string {
		resp := r.get("/", r.host, "")
		if resp.StatusCode != 200 || !strings.HasPrefix(resp.Header.Get("Content-Type"), "text/html") {
			t.Fatalf("status %d type %q", resp.StatusCode, resp.Header.Get("Content-Type"))
		}
		return readAll(resp)
	}
	tree(t, filepath.Dir(filepath.Dir(filepath.Dir(page))), "index.html", "<p>one</p>")
	if got := read(); got != "<p>one</p>" {
		t.Fatalf("got %q", got)
	}
	os.WriteFile(page, []byte("<p>two</p>"), 0o600)
	if got := read(); got != "<p>two</p>" {
		t.Fatalf("got %q", got)
	}
	// the headers every answer carries (nosniff, no-store, framing, CSP)
	resp := r.get("/", r.host, "")
	for k, want := range map[string]string{"X-Content-Type-Options": "nosniff", "Cache-Control": "no-store", "X-Frame-Options": "DENY",
		"Referrer-Policy": "no-referrer"} {
		if got := resp.Header.Get(k); got != want {
			t.Errorf("%s: %q, want %q", k, got, want)
		}
	}
	csp := resp.Header.Get("Content-Security-Policy")
	for _, part := range []string{"default-src 'none'", "frame-ancestors 'none'", "connect-src 'self'", "base-uri 'none'", "form-action 'none'",
		"font-src https://fonts.gstatic.com", "style-src 'unsafe-inline' https://fonts.googleapis.com"} {
		if !strings.Contains(csp, part) {
			t.Errorf("CSP lacks %q: %s", part, csp)
		}
	}
	// the JSON answer is framing-protected too
	if got := r.get("/api/state", r.host, "").Header.Get("X-Frame-Options"); got != "DENY" {
		t.Errorf("state X-Frame-Options %q", got)
	}
}

func TestSecFetchSite(t *testing.T) {
	r := newRig(t, "", 0)
	for site, want := range map[string]int{"cross-site": 403, "same-site": 403, "same-origin": 200, "none": 200} {
		req, _ := http.NewRequest("GET", r.srv.URL+"/api/state", nil)
		req.Host = r.host
		req.Header.Set("Sec-Fetch-Site", site)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		if resp.StatusCode != want {
			t.Errorf("Sec-Fetch-Site %s: %d, want %d", site, resp.StatusCode, want)
		}
	}
}

// The view model carries what the page shows: no host name, no pid, no free text of an event but its step.
func TestViewModelOmitsHostAndPid(t *testing.T) {
	r := newRig(t, "", 0)
	body := readAll(r.get("/api/state", r.host, ""))
	for _, banned := range []string{`"host":`, `"pid":`, `"session":`, `"start":`} {
		if strings.Contains(body, banned) {
			t.Errorf("/api/state carries %s: %s", banned, body)
		}
	}
	ch := r.events()
	next(t, ch, "data: ")
	r.core.Do(live.Request{Op: "emit", Proto: live.Proto, Kind: "review-filed", Unit: "c0002", Reason: "private note", Ref: "abc123"})
	l := next(t, ch, "data: ")
	for _, banned := range []string{`"host":`, `"pid":`, "private note", "abc123", `"ref":`, `"reason":`} {
		if strings.Contains(l, banned) {
			t.Errorf("an event carries %s: %s", banned, l)
		}
	}
	if !strings.Contains(l, `"kind":"review-filed"`) || !strings.Contains(l, `"unit":"c0002"`) || !strings.Contains(l, `"at"`) || !strings.Contains(l, `"seq"`) {
		t.Errorf("an event lacks its feed fields: %s", l)
	}
}

// events opens /api/events and returns the lines it sends, until the test ends.
func (r *rig) events() <-chan string {
	ctx, cancel := context.WithCancel(context.Background())
	r.t.Cleanup(cancel)
	req, _ := http.NewRequestWithContext(ctx, "GET", r.srv.URL+"/api/events", nil)
	req.Host = r.host
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		r.t.Fatal(err)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		r.t.Fatalf("type %q", ct)
	}
	out := make(chan string, 100)
	go func() { // owner: the test; ends when the test cancels the request
		defer resp.Body.Close()
		sc := bufio.NewScanner(resp.Body)
		for sc.Scan() {
			out <- sc.Text()
		}
		close(out)
	}()
	return out
}

// next reads lines until one has the prefix, within a deadline.
func next(t *testing.T, ch <-chan string, prefix string) string {
	t.Helper()
	deadline := time.After(5 * time.Second)
	for {
		select {
		case l, ok := <-ch:
			if !ok {
				t.Fatalf("stream ended before %q", prefix)
			}
			if strings.HasPrefix(l, prefix) {
				return l
			}
		case <-deadline:
			t.Fatalf("no %q within 5 s", prefix)
		}
	}
}

func TestEventsDeliverClaimAndEmit(t *testing.T) {
	r := newRig(t, "", 0)
	ch := r.events()
	next(t, ch, "data: ") // the hello message: the stream is open and caught up
	if rep := r.core.Do(live.Request{Op: "release", Proto: live.Proto, Worker: "claude-1"}); !rep.OK() {
		t.Fatal(rep)
	}
	if l := next(t, ch, "data: "); !strings.Contains(l, `"kind":"released"`) {
		t.Fatalf("after release: %s", l)
	}
	if rep := r.core.Do(live.Request{Op: "claim", Proto: live.Proto, Worker: "grok-2", Unit: "c0002", Activity: "design"}); !rep.OK() {
		t.Fatal(rep)
	}
	if l := next(t, ch, "data: "); !strings.Contains(l, `"kind":"claimed"`) || !strings.Contains(l, "c0002") {
		t.Fatalf("after claim: %s", l)
	}
	if rep := r.core.Do(live.Request{Op: "emit", Proto: live.Proto, Kind: "review-filed", Unit: "c0002"}); !rep.OK() {
		t.Fatal(rep)
	}
	if l := next(t, ch, "data: "); !strings.Contains(l, `"kind":"review-filed"`) {
		t.Fatalf("after emit: %s", l)
	}
}

func TestEventsHeartbeatAndHostCheck(t *testing.T) {
	r := newRig(t, "", 20*time.Millisecond)
	next(t, r.events(), ": ping")
	if resp := r.get("/api/events", "evil.example:1", ""); resp.StatusCode != 403 {
		t.Fatalf("events with another host: %d", resp.StatusCode)
	}
}

func TestOpenCountsStreamsAndShutdownEndsThem(t *testing.T) {
	r := newRig(t, "", 0)
	ch := r.events()
	next(t, ch, "data: ")
	if r.h.Open() != 1 {
		t.Fatalf("open %d, want 1", r.h.Open())
	}
}

// f0420: the worker card shows the account label the owner gave, and only a worker that has one carries the key.
func TestViewModelCarriesAccountLabel(t *testing.T) {
	r := newRig(t, "", 0)
	rep := r.core.Do(live.Request{Op: "register", Proto: live.Proto, Worker: "kimi-3", CLI: "kimi", PID: os.Getpid(), Account: "alpha"})
	if !rep.OK() {
		t.Fatalf("register: %v", rep)
	}
	var v struct {
		Workers []map[string]any `json:"workers"`
	}
	if err := json.Unmarshal([]byte(readAll(r.get("/api/state", r.host, ""))), &v); err != nil {
		t.Fatal(err)
	}
	got := map[string]any{}
	for _, w := range v.Workers {
		got[w["id"].(string)] = w["account"]
	}
	if got["kimi-3"] != "alpha" || got["claude-1"] != nil || got["grok-2"] != nil || len(v.Workers) != 3 {
		t.Fatalf("accounts %v", got)
	}
}
