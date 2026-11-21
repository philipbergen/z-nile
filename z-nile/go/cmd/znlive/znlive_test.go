package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"testing"
	"time"

	"znile/internal/live"
	"znile/internal/where"
	"znile/internal/wire"
)

var binary string // the built znlive, shared by every test

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "znlive-test-bin")
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	binary = filepath.Join(dir, "znlive")
	goBin := filepath.Join(runtime.GOROOT(), "bin", "go")
	if out, err := exec.Command(goBin, "build", "-o", binary, ".").CombinedOutput(); err != nil {
		fmt.Fprintf(os.Stderr, "go build: %v\n%s", err, out)
		os.RemoveAll(dir)
		os.Exit(1)
	}
	code := m.Run()
	os.RemoveAll(dir)
	os.Exit(code)
}

// rig is one throwaway state directory, with the daemons and sockets of one test.
type rig struct {
	t    *testing.T
	tmp  string // short, so the socket path stays under sun_path; the daemons' TMPDIR
	dir  string // the state directory
	pids []*exec.Cmd
}

func newRig(t *testing.T) *rig {
	t.Helper()
	tmp, err := os.MkdirTemp("", "zl")
	if err != nil {
		t.Fatal(err)
	}
	r := &rig{t: t, tmp: tmp, dir: filepath.Join(tmp, "state")}
	t.Cleanup(func() {
		for _, c := range r.pids {
			if c.ProcessState == nil {
				c.Process.Kill()
				c.Wait()
			}
			if syscall.Kill(c.Process.Pid, 0) == nil {
				t.Errorf("daemon %d is still alive", c.Process.Pid)
			}
		}
		os.RemoveAll(tmp)
	})
	return r
}

func (r *rig) env() []string {
	return append(os.Environ(), "TMPDIR="+r.tmp, "ZN_LIVE_DIR=", "ZN_WORKER=")
}

// serve starts a daemon; it returns once the socket answers.
func (r *rig) serve(dir string, args ...string) *exec.Cmd {
	r.t.Helper()
	cmd := exec.Command(binary, append([]string{"serve", "--dir", dir, "--idle-exit", "30s"}, args...)...)
	cmd.Env = r.env()
	if err := cmd.Start(); err != nil {
		r.t.Fatal(err)
	}
	r.pids = append(r.pids, cmd)
	for i := 0; i < 500; i++ {
		if code, _, _ := r.zn(dir, "status"); code == 0 {
			return cmd
		}
		time.Sleep(10 * time.Millisecond)
	}
	r.t.Fatal("the daemon did not start")
	return nil
}

func (r *rig) zn(dir string, args ...string) (int, string, string) {
	cmd := exec.Command(binary, append(args, "--dir", dir)...)
	cmd.Env = r.env()
	var out, errb bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errb
	err := cmd.Run()
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	} else if err != nil {
		r.t.Fatal(err)
	}
	return code, out.String(), errb.String()
}

func (r *rig) kill9(c *exec.Cmd) {
	c.Process.Kill()
	c.Wait()
}

func parse(t *testing.T, s string) map[string]any {
	t.Helper()
	m := map[string]any{}
	if err := json.Unmarshal([]byte(strings.TrimSpace(s)), &m); err != nil {
		t.Fatalf("not one JSON object: %q", s)
	}
	return m
}

// the design's full count: 20 processes, 50 rounds; it takes under two seconds
const nRounds, nProcs = 50, 20

// AC10: of 20 `znlive claim` processes started together, in each round exactly one exits 0 and the others 1.
func TestProcessRaceOneWinner(t *testing.T) {
	r := newRig(t)
	r.serve(r.dir)
	for i := 0; i < nProcs; i++ {
		if code, out, errb := r.zn(r.dir, "register", "--worker", fmt.Sprint("p", i), "--cli", "t", "--pid", fmt.Sprint(os.Getpid())); code != 0 {
			t.Fatalf("register: %d %s %s", code, out, errb)
		}
	}
	for round := 0; round < nRounds; round++ {
		cmds := make([]*exec.Cmd, nProcs)
		pipes := make([]io.WriteCloser, nProcs)
		outs := make([]*bytes.Buffer, nProcs)
		for i := range cmds {
			// each process waits on its stdin, so the claims leave together
			c := exec.Command("sh", "-c", `read x; exec "$0" claim --dir "$1" --worker "$2" --unit R1 --activity design`,
				binary, r.dir, fmt.Sprint("p", i))
			c.Env = r.env()
			outs[i] = &bytes.Buffer{}
			c.Stdout = outs[i]
			w, err := c.StdinPipe()
			if err != nil {
				t.Fatal(err)
			}
			pipes[i] = w
			if err := c.Start(); err != nil {
				t.Fatal(err)
			}
			cmds[i] = c
		}
		for i := range cmds {
			io.WriteString(pipes[i], "go\n")
			pipes[i].Close()
		}
		winner, wins, held := "", 0, 0
		for i, c := range cmds {
			err := c.Wait()
			switch {
			case err == nil:
				wins++
				winner = fmt.Sprint("p", i)
			case c.ProcessState.ExitCode() == 1 && strings.Contains(outs[i].String(), `"refused":"held"`):
				held++
			default:
				t.Fatalf("round %d p%d: %v %s", round, i, err, outs[i])
			}
		}
		if wins != 1 || held != nProcs-1 {
			t.Fatalf("round %d: %d winners, %d held", round, wins, held)
		}
		if code, out, _ := r.zn(r.dir, "release", "--worker", winner); code != 0 {
			t.Fatalf("release: %s", out)
		}
	}
}

// AC11: a second serve on one state directory exits and the first keeps answering; a restart after kill -9
// replaces the stale socket.
func TestSecondServeAndRestart(t *testing.T) {
	r := newRig(t)
	first := r.serve(r.dir)
	cmd := exec.Command(binary, "serve", "--dir", r.dir)
	cmd.Env = r.env()
	var errb bytes.Buffer
	cmd.Stderr = &errb
	done := make(chan error, 1)
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		if ee, ok := err.(*exec.ExitError); !ok || ee.ExitCode() != 3 || !strings.Contains(errb.String(), "another daemon") {
			t.Fatalf("second serve: %v %q", err, errb.String())
		}
	case <-time.After(5 * time.Second):
		cmd.Process.Kill()
		<-done
		t.Fatal("the second serve did not exit")
	}
	if code, _, _ := r.zn(r.dir, "status"); code != 0 {
		t.Fatal("the first daemon stopped answering")
	}
	sock := where.ClientSocket(mustReal(t, r.dir))
	r.kill9(first)
	if _, err := os.Stat(sock); err != nil {
		t.Fatalf("kill -9 should leave a stale socket: %v", err)
	}
	if code, _, _ := r.zn(r.dir, "status"); code != 3 {
		t.Fatalf("a dead daemon's status exited %d, want 3", code)
	}
	r.serve(r.dir)
	code, out, _ := r.zn(r.dir, "status")
	if code != 0 || parse(t, out)["ok"] != true {
		t.Fatalf("after the restart: %d %s", code, out)
	}
}

func mustReal(t *testing.T, dir string) string {
	t.Helper()
	real, err := filepath.EvalSymlinks(dir)
	if err != nil {
		t.Fatal(err)
	}
	return real
}

// AC12: a 200-character state directory still gets a short socket; the socket is 0600 and the directory 0700; a
// request naming another state directory exits 3.
func TestLongDirModesAndWrongDir(t *testing.T) {
	r := newRig(t)
	long := r.tmp
	for len(long) < 200 {
		long = filepath.Join(long, strings.Repeat("d", 50))
	}
	long = long[:200]
	r.serve(long)
	real := mustReal(t, long)
	sock := where.ClientSocket(real)
	if len(sock) > 103 {
		t.Fatalf("socket path is %d bytes", len(sock))
	}
	if st, err := os.Stat(sock); err != nil || st.Mode().Perm() != 0o600 {
		t.Fatalf("socket %v %v", st, err)
	}
	if st, err := os.Stat(real); err != nil || st.Mode().Perm() != 0o700 {
		t.Fatalf("state dir %v %v", st, err)
	}
	_, out, _ := r.zn(long, "status")
	if got := parse(t, out)["socket"]; got != sock {
		t.Fatalf("status socket %v, want %s", got, sock)
	}
	// a client of another state directory that follows a pointer to this daemon
	other := filepath.Join(r.tmp, "other")
	if err := os.MkdirAll(other, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(other, "socket"), []byte(sock+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	code, out, errb := r.zn(other, "status")
	if code != 3 || out != "" || !strings.Contains(errb, "serves") {
		t.Fatalf("wrong dir: exit %d stdout %q stderr %q", code, out, errb)
	}
	// and the same over the wire by hand, with a wrong protocol
	conn, err := wire.Dial(sock)
	if err != nil {
		t.Fatal(err)
	}
	res, err := wire.Call(conn, live.Request{Op: "status", Dir: real, Proto: 99}, 5*time.Second)
	if err != nil || res.Reply.Refused() != "proto" {
		t.Fatalf("proto: %v %v", res.Reply, err)
	}
}

func waitExit(t *testing.T, c *exec.Cmd, within time.Duration) time.Duration {
	t.Helper()
	done := make(chan struct{})
	go func() { c.Wait(); close(done) }()
	t0 := time.Now()
	select {
	case <-done:
		return time.Since(t0)
	case <-time.After(within):
		c.Process.Kill()
		<-done
		t.Fatalf("the daemon did not exit within %s", within)
		return 0
	}
}

func hasSnapshot(t *testing.T, dir string) {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(dir, "snapshot.json"))
	if err != nil {
		t.Fatalf("no snapshot at exit: %v", err)
	}
	var s live.Snapshot
	if err := json.Unmarshal(b, &s); err != nil {
		t.Fatal(err)
	}
}

// AC13: an idle daemon exits after --idle-exit, a daemon whose binary is replaced exits within its check interval,
// SIGTERM and shutdown exit too; each writes the snapshot.
func TestIdleExit(t *testing.T) {
	r := newRig(t)
	d := r.serve(r.dir, "--idle-exit", "1s")
	if el := waitExit(t, d, 6*time.Second); el < 500*time.Millisecond {
		t.Fatalf("left after %s, before the idle time", el)
	}
	hasSnapshot(t, r.dir)
}

func TestBinaryReplacedExits(t *testing.T) {
	r := newRig(t)
	copyOf := filepath.Join(r.tmp, "znlive")
	b, err := os.ReadFile(binary)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(copyOf, b, 0o755); err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(copyOf, "serve", "--dir", r.dir, "--idle-exit", "30s", "--check-every", "1s")
	cmd.Env = r.env()
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	r.pids = append(r.pids, cmd)
	for i := 0; i < 500; i++ {
		if code, _, _ := r.zn(r.dir, "status"); code == 0 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	// a registered worker keeps the idle rule out of it: only the replaced binary can end this daemon
	r.zn(r.dir, "register", "--worker", "w", "--cli", "t", "--pid", fmt.Sprint(os.Getpid()))
	time.Sleep(1500 * time.Millisecond)
	if code, _, _ := r.zn(r.dir, "status"); code != 0 {
		t.Fatal("the daemon left before its binary was replaced")
	}
	fresh := copyOf + ".new"
	if err := os.WriteFile(fresh, append(b, '\n'), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(fresh, copyOf); err != nil {
		t.Fatal(err)
	}
	waitExit(t, cmd, 4*time.Second)
	hasSnapshot(t, r.dir)
}

func TestSignalAndShutdownExit(t *testing.T) {
	r := newRig(t)
	d := r.serve(r.dir)
	d.Process.Signal(syscall.SIGTERM)
	waitExit(t, d, 5*time.Second)
	hasSnapshot(t, r.dir)
	d = r.serve(r.dir)
	if code, out, _ := r.zn(r.dir, "shutdown"); code != 0 {
		t.Fatalf("shutdown: %d %s", code, out)
	}
	waitExit(t, d, 5*time.Second)
}

// AC7 and AC8 through real processes: kill -9, a torn tail, a restart.
func TestKill9TornTailRestart(t *testing.T) {
	r := newRig(t)
	d := r.serve(r.dir)
	me := fmt.Sprint(os.Getpid())
	r.zn(r.dir, "register", "--worker", "w", "--cli", "t", "--pid", me, "--can", "design/1")
	if code, out, _ := r.zn(r.dir, "claim", "--worker", "w", "--unit", "u", "--activity", "design"); code != 0 {
		t.Fatal(out)
	}
	_, out, _ := r.zn(r.dir, "status")
	seq := parse(t, out)["seq"]
	r.kill9(d)
	f, err := os.OpenFile(filepath.Join(r.dir, "events.jsonl"), os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	f.WriteString(`{"seq":50,"kind":"cl`)
	f.Close()
	r.serve(r.dir)
	_, out, _ = r.zn(r.dir, "status")
	st := parse(t, out)
	if st["seq"] != seq || st["repaired"] != float64(1) || st["workers"] != float64(1) || st["claims"] != float64(1) {
		t.Fatalf("after restart %v (seq was %v)", st, seq)
	}
	if code, out, _ := r.zn(r.dir, "release", "--worker", "w"); code != 0 {
		t.Fatalf("the restored claim could not be released: %d %s", code, out)
	}
}
