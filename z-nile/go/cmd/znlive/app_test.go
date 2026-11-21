package main

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// pagefile writes a one-line app page under the rig's folder.
func (r *rig) pagefile() string {
	r.t.Helper()
	p := filepath.Join(r.tmp, "index.html")
	if err := os.WriteFile(p, []byte("<title>page</title>"), 0o600); err != nil {
		r.t.Fatal(err)
	}
	return p
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
