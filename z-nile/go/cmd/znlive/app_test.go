package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"

	"znile/internal/live"
	"znile/internal/web"
	"znile/internal/where"
	"znile/internal/wire"
)

// pagefile writes a one-line app page under the rig's folder, where the daemon allows one (z-nile/app/index.html).
func (r *rig) pagefile() string { return r.pageNamed("a", "<title>page</title>") }

// pageNamed writes an app page in its own checkout-shaped folder <tmp>/<dir>/z-nile/app/index.html.
func (r *rig) pageNamed(dir, text string) string {
	r.t.Helper()
	d := filepath.Join(r.tmp, dir, "z-nile", "app")
	if err := os.MkdirAll(d, 0o700); err != nil {
		r.t.Fatal(err)
	}
	p := filepath.Join(d, "index.html")
	if err := os.WriteFile(p, []byte(text), 0o600); err != nil {
		r.t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(d, "live.js"), []byte("var x;"), 0o600); err != nil {
		r.t.Fatal(err)
	}
	return p
}

// startServe starts `serve` by hand (not stopped by the rig) and returns the command and its http address once it serves.
func (r *rig) startServe(args ...string) *exec.Cmd {
	r.t.Helper()
	cmd := exec.Command(binary, append([]string{"serve", "--dir", r.dir, "--http"}, args...)...)
	cmd.Env = r.env()
	if err := cmd.Start(); err != nil {
		r.t.Fatal(err)
	}
	r.pids = append(r.pids, cmd)
	for i := 0; i < 500; i++ {
		if _, err := os.Stat(filepath.Join(r.dir, "http")); err == nil {
			return cmd
		}
		time.Sleep(10 * time.Millisecond)
	}
	r.t.Fatal("the daemon did not serve")
	return nil
}

func (r *rig) httpURL() string {
	b, err := os.ReadFile(filepath.Join(r.dir, "http"))
	if err != nil {
		r.t.Fatal(err)
	}
	return "http://" + strings.TrimSpace(string(b)) + "/"
}

func httpGet(t *testing.T, url string) (int, string) {
	t.Helper()
	c := &http.Client{Timeout: 5 * time.Second}
	resp, err := c.Get(url)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

// Serving is opt-in: a daemon that a write op starts, and one started by hand, open no port and write no address.
func TestHTTPOffByDefault(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	if code, out, errb := r.zn(r.dir, "emit", "review-filed"); code != 0 {
		t.Fatalf("emit: %d %s %s", code, out, errb)
	}
	if _, err := os.Stat(filepath.Join(r.dir, "http")); err == nil {
		t.Fatal("an auto-started daemon wrote an http address")
	}
	if b, _ := os.ReadFile(filepath.Join(r.dir, "daemon.log")); strings.Contains(string(b), "http") {
		t.Fatalf("the daemon log mentions http: %s", b)
	}
}

// `app` starts the daemon when none runs, asks it to serve, prints the URL; the page and the state answer on it; a second
// `app` prints the same URL; the address file and the port go away with the daemon.
func TestAppServesAndIsIdempotent(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	page := r.pagefile()
	if code, out, errb := r.zn(r.dir, "register", "--worker", "w1", "--cli", "fake", "--pid", fmt.Sprint(os.Getpid()),
		"--can", "code/light"); code != 0 {
		t.Fatalf("register: %d %s %s", code, out, errb)
	}
	code, out, errb := r.zn(r.dir, "app", "--page", page)
	url := strings.TrimSpace(out)
	if code != 0 || !strings.HasPrefix(url, "http://127.0.0.1:") || !strings.HasSuffix(url, "/") {
		t.Fatalf("app: %d %q %s", code, out, errb)
	}
	if b, err := os.ReadFile(filepath.Join(r.dir, "http")); err != nil || strings.TrimSpace(string(b)) != strings.TrimSuffix(strings.TrimPrefix(url, "http://"), "/") {
		t.Fatalf("http file: %v %q for %s", err, b, url)
	}
	if code, body := httpGet(t, url); code != 200 || body != "<title>page</title>" {
		t.Fatalf("/: %d %q", code, body)
	}
	code2, body := httpGet(t, url+"api/state")
	if code2 != 200 || !strings.Contains(body, `"id":"w1"`) || !strings.Contains(body, `"cli":"fake"`) {
		t.Fatalf("/api/state: %d %s", code2, body)
	}
	if code, out, _ := r.zn(r.dir, "app", "--page", page); code != 0 || strings.TrimSpace(out) != url {
		t.Fatalf("second app: %d %q, want %s", code, out, url)
	}
	addr := strings.TrimSuffix(strings.TrimPrefix(url, "http://"), "/")
	r.stopAutostarted(r.dir)
	if _, err := os.Stat(filepath.Join(r.dir, "http")); err == nil {
		t.Fatal("the http file stays after the daemon exits")
	}
	if c, err := net.DialTimeout("tcp", addr, 500*time.Millisecond); err == nil {
		c.Close()
		t.Fatal("the port still answers after the daemon exited")
	}
}

// The app page must exist, and a busy port is a refusal that names it.
func TestAppRefusals(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	code, _, errb := r.zn(r.dir, "app", "--page", filepath.Join(r.tmp, "missing.html"))
	if code != exitUnavailable || !strings.Contains(errb, "missing.html") {
		t.Fatalf("missing page: %d %s", code, errb)
	}
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer busy.Close()
	port := busy.Addr().(*net.TCPAddr).Port
	code, _, errb = r.zn(r.dir, "app", "--page", r.pagefile(), "--port", fmt.Sprint(port))
	if code != exitUnavailable || !strings.Contains(errb, fmt.Sprint(port)) {
		t.Fatalf("busy port: %d %s", code, errb)
	}
	if code, _, _ := r.zn(r.dir, "app", "--page", r.pagefile(), "--port", "70000"); code != exitUsage {
		t.Fatalf("port 70000: %d", code)
	}
}

// `serve --http` serves from the start; the daemon stops cleanly with open event streams.
func TestServeHTTPFlag(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	cmd := r.serve(r.dir, "--http", "--page", r.pagefile())
	b, err := os.ReadFile(filepath.Join(r.dir, "http"))
	if err != nil {
		t.Fatal(err)
	}
	url := "http://" + strings.TrimSpace(string(b)) + "/"
	if code, body := httpGet(t, url); code != 200 || body != "<title>page</title>" {
		t.Fatalf("/: %d %q", code, body)
	}
	resp, err := http.Get(url + "api/events")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	r.zn(r.dir, "shutdown")
	done := make(chan struct{})
	go func() { cmd.Wait(); close(done) }() // owner: this test; ends when the daemon exits
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		syscall.Kill(cmd.Process.Pid, syscall.SIGKILL)
		t.Fatal("the daemon did not exit with an event stream open")
	}
}

// G2: a second `app --page B` (an allowed B) replaces the page; a refused one keeps the current page and exits 2.
func TestAppPageSwapAndRefusals(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	a, b := r.pageNamed("a", "<p>A</p>"), r.pageNamed("b", "<p>B</p>")
	_, out, errb := r.zn(r.dir, "app", "--page", a)
	url := strings.TrimSpace(out)
	if code, body := httpGet(t, url); code != 200 || body != "<p>A</p>" {
		t.Fatalf("A: %d %q %s", code, body, errb)
	}
	if code, _, errb := r.zn(r.dir, "app", "--page", b); code != 0 {
		t.Fatalf("app B: %d %s", code, errb)
	}
	if _, body := httpGet(t, url); body != "<p>B</p>" {
		t.Fatalf("the second page was not served: %q", body)
	}
	other := filepath.Join(r.tmp, "hosts.txt")
	os.WriteFile(other, []byte("secret"), 0o600)
	wrongName := filepath.Join(r.tmp, "a", "z-nile", "app", "other.html")
	os.WriteFile(wrongName, []byte("x"), 0o600)
	link := filepath.Join(r.tmp, "c", "z-nile", "app", "index.html")
	os.MkdirAll(filepath.Dir(link), 0o700)
	os.Symlink(other, link)
	for _, bad := range []string{"/etc/hosts", other, wrongName, link} {
		code, _, errb := r.zn(r.dir, "app", "--page", bad)
		if code != exitUsage || strings.Contains(errb, r.tmp) {
			t.Errorf("--page %s: exit %d, stderr %q", bad, code, errb)
		}
		if _, body := httpGet(t, url); body != "<p>B</p>" {
			t.Fatalf("after a refused swap the page is %q", body)
		}
	}
	// a raw request with a relative path is refused by the daemon itself
	real, _ := filepath.EvalSymlinks(r.dir)
	conn, err := wire.Dial(where.ClientSocket(real), filepath.Join(real, "lock"))
	if err != nil {
		t.Fatal(err)
	}
	res, err := wire.Call(conn, live.Request{Op: "app", Proto: live.Proto, Dir: real, Page: "z-nile/app/index.html"}, 5*time.Second, nil)
	if err != nil || res.Reply.OK() || res.Reply.Refused() != "page" {
		t.Fatalf("relative page: %v %v", res.Reply, err)
	}
	if _, body := httpGet(t, url); body != "<p>B</p>" {
		t.Fatalf("after the raw request the page is %q", body)
	}
}

// For the default state folder the page must lie in the repository or one of its worktrees; the daemon decides.
func TestAppdRootRule(t *testing.T) {
	root := t.TempDir()
	root, _ = filepath.EvalSymlinks(root)
	mk := func(base string) string {
		d := filepath.Join(base, "z-nile", "app")
		os.MkdirAll(d, 0o700)
		p := filepath.Join(d, "index.html")
		os.WriteFile(p, []byte("<p>"+base+"</p>"), 0o600)
		os.WriteFile(filepath.Join(d, "live.js"), []byte("var x;"), 0o600)
		return p
	}
	main, wt, outside := mk(root), mk(filepath.Join(root, ".worktree", "w1")), mk(t.TempDir())
	state := filepath.Join(root, ".cache", "live")
	os.MkdirAll(state, 0o700)
	ctx, cancel := context.WithCancel(context.Background())
	a := &appd{ctx: ctx, core: live.New(live.Config{}), dir: state, root: root, stderr: io.Discard}
	t.Cleanup(func() { cancel(); a.close() })
	if _, err := a.ensure(0, outside); err == nil || !web.IsPage(err) {
		t.Fatalf("a page outside the repository: %v", err)
	}
	if a.h != nil {
		t.Fatal("a refused first page still opened a port")
	}
	addr, err := a.ensure(0, wt)
	if err != nil {
		t.Fatal(err)
	}
	if _, body := httpGet(t, "http://"+addr+"/"); !strings.Contains(body, "w1") {
		t.Fatalf("worktree page: %q", body)
	}
	if _, err := a.ensure(0, outside); err == nil {
		t.Fatal("a swap to a page outside the repository was accepted")
	}
	// the worktree goes away: the main checkout's page answers, and no path is sent
	os.RemoveAll(filepath.Join(root, ".worktree"))
	code, body := httpGet(t, "http://"+addr+"/")
	if code != 200 || body != "<p>"+root+"</p>" {
		t.Fatalf("fallback: %d %q", code, body)
	}
	_ = main
}

// G7 and the idle exit: an open event stream keeps the daemon up past its idle limit; the daemon exits soon after it closes.
func TestIdleExitWaitsForOpenStream(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	cmd := r.startServe("--page", r.pagefile(), "--idle-exit", "700ms")
	resp, err := http.Get(r.httpURL() + "api/events")
	if err != nil {
		t.Fatal(err)
	}
	time.Sleep(2200 * time.Millisecond) // three idle limits with the stream open
	if code, _, _ := r.zn(r.dir, "status"); code != 0 {
		t.Fatal("the daemon idled out with an event stream open")
	}
	resp.Body.Close()
	done := make(chan struct{})
	go func() { cmd.Wait(); close(done) }() // owner: this test; ends when the daemon exits
	select {
	case <-done:
	case <-time.After(6 * time.Second):
		t.Fatal("the daemon did not idle out after the stream closed")
	}
}

// M13: shutdown ends an open stream at once, not after the drain fallback.
func TestShutdownEndsOpenStreamQuickly(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.startServe("--page", r.pagefile())
	resp, err := http.Get(r.httpURL() + "api/events")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	ended := make(chan struct{})
	go func() { io.Copy(io.Discard, resp.Body); close(ended) }() // owner: this test; ends with the stream
	t0 := time.Now()
	r.zn(r.dir, "shutdown")
	select {
	case <-ended:
	case <-time.After(5 * time.Second):
		t.Fatal("the stream is still open after shutdown")
	}
	if d := time.Since(t0); d > time.Second {
		t.Fatalf("the stream ended after %v, want under 1 s", d)
	}
}

// M14: a stale address file (a killed daemon leaves one) is removed when a daemon starts, serving or not.
func TestStaleHTTPFileRemovedAtStart(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	os.MkdirAll(r.dir, 0o700)
	stale := filepath.Join(r.dir, "http")
	os.WriteFile(stale, []byte("127.0.0.1:1\n"), 0o600)
	r.serve(r.dir)
	if _, err := os.Stat(stale); err == nil {
		t.Fatal("a stale http file survived the start of a daemon that does not serve")
	}
}

// The port a daemon served on is asked for first by the next `app`, so an open tab finds its daemon again; a busy port falls back.
func TestAppKeepsItsPortAcrossRestart(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	page := r.pagefile()
	_, out, errb := r.zn(r.dir, "app", "--page", page)
	first := strings.TrimSpace(out)
	if first == "" {
		t.Fatalf("app: %s", errb)
	}
	r.stopAutostarted(r.dir)
	_, out, _ = r.zn(r.dir, "app", "--page", page)
	if strings.TrimSpace(out) != first {
		t.Fatalf("after a restart: %q, want %q", out, first)
	}
	// an auto-started daemon still opens nothing
	r.stopAutostarted(r.dir)
	r.zn(r.dir, "emit", "review-filed")
	if _, err := os.Stat(filepath.Join(r.dir, "http")); err == nil {
		t.Fatal("an auto-started daemon opened the remembered port")
	}
	r.stopAutostarted(r.dir)
	port := portOf(strings.TrimSuffix(strings.TrimPrefix(first, "http://"), "/"))
	busy, err := net.Listen("tcp", "127.0.0.1:"+port)
	if err != nil {
		t.Skipf("the port was taken meanwhile: %v", err)
	}
	defer busy.Close()
	code, out, errb := r.zn(r.dir, "app", "--page", page)
	if code != 0 || strings.TrimSpace(out) == first || !strings.HasPrefix(out, "http://127.0.0.1:") {
		t.Fatalf("with the old port busy: %d %q %s", code, out, errb)
	}
}

// A second `app` asking for another port than the one served is refused with the address it serves on.
func TestAppAnotherPortRefused(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	page := r.pagefile()
	_, out, _ := r.zn(r.dir, "app", "--page", page)
	addr := strings.TrimSuffix(strings.TrimPrefix(strings.TrimSpace(out), "http://"), "/")
	other := 40000
	if fmt.Sprint(other) == portOf(addr) {
		other++
	}
	code, _, errb := r.zn(r.dir, "app", "--page", page, "--port", fmt.Sprint(other))
	if code != exitUnavailable || !strings.Contains(errb, addr) {
		t.Fatalf("another port: %d %q", code, errb)
	}
}

// F9: a daemon (or a binary) that does not know `app` gets a message that says what to do.
func TestUnknownOpMessage(t *testing.T) {
	var out, errb bytes.Buffer
	res := wire.Result{Reply: live.Reply{"ok": false, "refused": "usage", "why": "unknown op app"}}
	if code := refusal("app", "/x", res, &out, &errb); code != exitUnavailable || !strings.Contains(errb.String(), "older build") {
		t.Fatalf("%d %q", code, errb.String())
	}
}
