package main

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func workerList(t *testing.T, r *rig) []any {
	t.Helper()
	code, out, errb := r.zn(r.dir, "workers")
	if code != 0 {
		t.Fatalf("workers: %d %s", code, errb)
	}
	return parse(t, out)["workers"].([]any)
}

// F2: register never reads ZN_WORKER, so a subagent's register does not take its parent's id and release its claim.
func TestRegisterIgnoresZNWorker(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.serve(r.dir)
	me := fmt.Sprint(os.Getpid())
	r.zn(r.dir, "register", "--worker", "parent", "--cli", "t", "--pid", me)
	if code, out, _ := r.znEnv(r.dir, []string{"ZN_WORKER=parent"}, "claim", "--unit", "u", "--activity", "design"); code != 0 {
		t.Fatalf("claim by ZN_WORKER: %d %s", code, out) // the other ops do read it
	}
	code, out, errb := r.znEnv(r.dir, []string{"ZN_WORKER=parent"}, "register", "--cli", "t", "--pid", me, "--as", "sub1")
	if code != 0 || !strings.HasSuffix(parse(t, out)["worker"].(string), ".sub1") {
		t.Fatalf("register --as: %d %s %s", code, out, errb)
	}
	if n := len(workerList(t, r)); n != 2 {
		t.Fatalf("%d workers, want the parent and the subagent", n)
	}
	_, out, _ = r.zn(r.dir, "claims")
	if cl := parse(t, out)["claims"].([]any); len(cl) != 1 {
		t.Fatalf("the parent lost its claim: %s", out)
	}
}

// F16: a register takes its session from the CLI's own variable when --session is absent.
func TestRegisterSessionFromEnvironment(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.serve(r.dir)
	r.znEnv(r.dir, []string{"KIMI_SESSION_ID=kimi-1"}, "register", "--worker", "w", "--cli", "t", "--pid", fmt.Sprint(os.Getpid()))
	if got := workerList(t, r)[0].(map[string]any)["session"]; got != "kimi-1" {
		t.Fatalf("session %v", got)
	}
}

// F3: a follow prints each event as it arrives, in order, before the process ends; the timeout then exits 75.
func TestFollowPrintsWhileRunning(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	r.serve(r.dir)
	cmd := exec.Command(binary, "events", "--follow", "--timeout", "2", "--dir", r.dir)
	cmd.Env = r.env()
	out, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	lines := make(chan string, 8)
	go func() { // owner: this test; ends when the process closes its stdout
		sc := bufio.NewScanner(out)
		for sc.Scan() {
			lines <- sc.Text()
		}
		close(lines)
	}()
	time.Sleep(400 * time.Millisecond) // connected
	r.zn(r.dir, "poke", "--reason", "first")
	r.zn(r.dir, "poke", "--reason", "second")
	for _, want := range []string{"first", "second"} {
		select {
		case l := <-lines:
			if !strings.Contains(l, `"reason":"`+want+`"`) {
				t.Fatalf("got %s, want %s", l, want)
			}
		case <-time.After(2 * time.Second):
			t.Fatalf("%s was not printed while the follow ran", want)
		}
	}
	if cmd.ProcessState != nil {
		t.Fatal("the follow ended before its timeout")
	}
	err = cmd.Wait()
	if ee, ok := err.(*exec.ExitError); !ok || ee.ExitCode() != 75 {
		t.Fatalf("exit: %v", err)
	}
}

// F9 (AC13): a daemon with a --follow reader connected does not idle-exit, and does once the reader is gone.
func TestIdleExitWaitsForFollowReader(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	d := r.serve(r.dir, "--idle-exit", "1s")
	cmd := exec.Command(binary, "events", "--follow", "--timeout", "4", "--dir", r.dir)
	cmd.Env = r.env()
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	time.Sleep(2500 * time.Millisecond)
	if d.ProcessState != nil || syscall.Kill(d.Process.Pid, 0) != nil {
		t.Fatal("the daemon idle-exited under a connected reader")
	}
	cmd.Wait()
	waitExit(t, d, 6*time.Second)
}

// F9 (AC4): with the default tick, a worker whose process was killed is released (lost) and removed within 3 s.
func TestDeadWorkerFreedWithinThreeSeconds(t *testing.T) {
	r := newRig(t)
	r.serve(r.dir) // the default liveness tick: 2 s
	child := exec.Command("sleep", "60")
	if err := child.Start(); err != nil {
		t.Fatal(err)
	}
	r.zn(r.dir, "register", "--worker", "dead", "--cli", "t", "--pid", fmt.Sprint(child.Process.Pid))
	if code, out, _ := r.zn(r.dir, "claim", "--worker", "dead", "--unit", "u", "--activity", "design"); code != 0 {
		t.Fatal(out)
	}
	child.Process.Kill()
	child.Wait() // reaped: no zombie
	t0 := time.Now()
	for {
		_, out, _ := r.zn(r.dir, "claims")
		if len(parse(t, out)["claims"].([]any)) == 0 {
			break
		}
		if time.Since(t0) > 3*time.Second {
			t.Fatalf("the claim was still held after 3 s")
		}
		time.Sleep(50 * time.Millisecond)
	}
	_, out, _ := r.zn(r.dir, "events")
	if !strings.Contains(out, `"kind":"released"`) || !strings.Contains(out, `"outcome":"lost"`) || !strings.Contains(out, `"kind":"gone"`) {
		t.Fatalf("events: %s", out)
	}
}

// F6: a daemon that cannot write its log answers exit 3 naming the log, not a refusal (exit 1).
func TestStorageFailureIsUnavailable(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	// a file-size limit of 2 blocks; the daemon ignores SIGXFSZ (Go does) so a write past it fails with EFBIG
	cmd := exec.Command("sh", "-c", `ulimit -f 2; exec "$0" serve --dir "$1" --idle-exit 30s`, binary, r.dir)
	cmd.Env = r.env()
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	r.pids = append(r.pids, cmd)
	settleUp(t, r)
	me := fmt.Sprint(os.Getpid())
	var code int
	var errb string
	for i := 0; i < 40 && code != 3; i++ { // each emitted event is a few hundred bytes
		code, _, errb = r.zn(r.dir, "register", "--worker", fmt.Sprint("w", i), "--cli", "t", "--pid", me)
	}
	if code != 3 || !strings.Contains(errb, filepath.Join(r.dir, "events.jsonl")) {
		t.Fatalf("exit %d stderr %q", code, errb)
	}
}

func settleUp(t *testing.T, r *rig) {
	t.Helper()
	for i := 0; i < 500; i++ {
		if code, _, _ := r.zn(r.dir, "status"); code == 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("the daemon did not start")
}

// F8: a second build with no source change leaves the binary alone (a rebuilt binary restarts a running daemon).
func TestGobuildSkipsUnchangedBuild(t *testing.T) {
	t.Parallel()
	root, err := filepath.Abs("../../../..") // the checkout: z-nile/go/cmd/znlive up four
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "z-nile", "lib", "gobuild.sh")); err != nil {
		t.Skip("not inside a checkout with z-nile/lib/gobuild.sh")
	}
	tmp, err := os.MkdirTemp("", "gb")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmp)
	out := filepath.Join(tmp, "bin", "znlive")
	build := func() string {
		cmd := exec.Command("bash", filepath.Join(root, "z-nile", "lib", "gobuild.sh"), root, out)
		var b bytes.Buffer
		cmd.Stdout, cmd.Stderr = &b, &b
		if err := cmd.Run(); err != nil {
			t.Fatalf("gobuild: %v\n%s", err, b.String())
		}
		return b.String()
	}
	build()
	first, _ := os.Stat(out)
	time.Sleep(1100 * time.Millisecond) // a rebuild would carry a later mtime
	msg := build()
	second, _ := os.Stat(out)
	if !os.SameFile(first, second) || !first.ModTime().Equal(second.ModTime()) || !strings.Contains(msg, "up to date") {
		t.Fatalf("the unchanged build replaced the binary: %q", msg)
	}
	if _, err := os.Stat(out + ".id"); err != nil {
		t.Fatal("no build id beside the binary")
	}
	if b, _ := os.ReadFile(out + ".id"); len(strings.TrimSpace(string(b))) != 12 {
		t.Fatalf("id %q", b)
	}
}
