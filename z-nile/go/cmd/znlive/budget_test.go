package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// f0424 review 1 finding 1: every one-shot op has a hard budget. Go ignores SIGALRM, so the budget is the client's own: a
// daemon that is stopped (SIGSTOP) accepts the connection and never answers, and the call must still end in exit 3.
func TestOneShotBudgetEndsAStoppedDaemonCall(t *testing.T) {
	r := newRig(t)
	d := r.serve(r.dir)
	if err := syscall.Kill(d.Process.Pid, syscall.SIGSTOP); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { syscall.Kill(d.Process.Pid, syscall.SIGCONT) })
	start := time.Now()
	code, out, errs := r.zn(r.dir, "claims")
	took := time.Since(start)
	if code != 3 || out != "" {
		t.Fatalf("a stopped daemon: want exit 3 and no output, got %d %q %q", code, out, errs)
	}
	if took < 1500*time.Millisecond || took > 3*time.Second {
		t.Fatalf("the default budget is 2 s; the call took %v", took)
	}
	if !strings.Contains(errs, "unavailable") {
		t.Fatalf("the sentence should say the layer is unavailable: %q", errs)
	}
}

func TestBudgetIsSettableAndWaitIsExempt(t *testing.T) {
	r := newRig(t)
	d := r.serve(r.dir)
	syscall.Kill(d.Process.Pid, syscall.SIGSTOP)
	t.Cleanup(func() { syscall.Kill(d.Process.Pid, syscall.SIGCONT) })
	start := time.Now()
	code, _, _ := r.znEnv(r.dir, []string{"ZN_LIVE_CALL_BUDGET=1"}, "status")
	if took := time.Since(start); code != 3 || took > 1800*time.Millisecond {
		t.Fatalf("budget 1 s: exit %d after %v", code, took)
	}
	syscall.Kill(d.Process.Pid, syscall.SIGCONT)
	if code, _, errs := r.zn(r.dir, "register", "--cli", "t", "--pid", strconv.Itoa(os.Getpid()), "--worker", "w"); code != 0 {
		t.Fatalf("register: %d %s", code, errs)
	}
	// a wait that outlives the budget ends by its own timeout (75), not by the budget
	start = time.Now()
	code, _, _ = r.znEnv(r.dir, []string{"ZN_LIVE_CALL_BUDGET=1"}, "wait", "--worker", "w", "--timeout", "2")
	if took := time.Since(start); code != 75 || took < 1800*time.Millisecond {
		t.Fatalf("wait is exempt from the budget: exit %d after %v", code, took)
	}
}

// finding 3: a check (the spec fence, a probe under ./zn run) never reaches the default state directory.
func TestChecksNeverReachTheDefaultStateDir(t *testing.T) {
	for _, marker := range []string{"PICKMAN_FENCE_SPECS=1", "PICKMAN_TEST_FENCE=/x", "ZN_BOUNDED_DEADLINE=99999999999"} {
		r := newRig(t)
		root := filepath.Join(r.tmp, "repo")
		if err := os.MkdirAll(filepath.Join(root, ".git"), 0o755); err != nil {
			t.Fatal(err)
		}
		run := func(env []string, op ...string) (int, string) {
			cmd := newCmd(r, root, append([]string{"ZN_LIVE_DIR=", "ZN_LIVE_ROOT=" + root}, env...), op...)
			out, _ := cmd.CombinedOutput()
			return exitCode(cmd), string(out)
		}
		code, msg := run([]string{marker}, "register", "--cli", "t", "--pid", strconv.Itoa(os.Getpid()))
		if code != 3 || !strings.Contains(msg, "refus") {
			t.Fatalf("%s: want exit 3 refusing, got %d %q", marker, code, msg)
		}
		if _, err := os.Stat(filepath.Join(root, ".cache")); err == nil {
			t.Fatalf("%s: the refusal created %s/.cache", marker, root)
		}
		// the explicit opt-in lets the op through to the usual answer for a default directory
		code, msg = run([]string{marker, "ZN_LIVE_ALLOW_DEFAULT=1"}, "status")
		if strings.Contains(msg, "refus") {
			t.Fatalf("%s with ZN_LIVE_ALLOW_DEFAULT=1 still refuses: %q", marker, msg)
		}
		// a named directory is never affected
		code, msg = run([]string{marker, "ZN_LIVE_DIR=" + filepath.Join(r.tmp, "named")}, "status")
		if strings.Contains(msg, "refus") {
			t.Fatalf("%s: a named directory was refused: %q", marker, msg)
		}
		_ = code
	}
}

func TestRelativeStateDirIsRefused(t *testing.T) {
	r := newRig(t)
	code, out, errs := r.znEnv(r.dir, []string{"ZN_LIVE_DIR=relative/state"}, "status")
	_ = out
	// --dir wins over the environment, so this run proves nothing yet: run without --dir
	cmd := newCmd(r, r.tmp, []string{"ZN_LIVE_DIR=relative/state"}, "status")
	b, _ := cmd.CombinedOutput()
	if exitCode(cmd) != 3 || !strings.Contains(string(b), "absolute") {
		t.Fatalf("a relative ZN_LIVE_DIR: want exit 3 naming 'absolute', got %d %q (with --dir: %d %q)", exitCode(cmd), b, code, errs)
	}
}

// newCmd is a client run in cwd with the rig's environment plus env (later entries win).
func newCmd(r *rig, cwd string, env []string, args ...string) *exec.Cmd {
	c := exec.Command(binary, args...)
	c.Dir = cwd
	c.Env = append(r.env(), env...)
	return c
}

func exitCode(c *exec.Cmd) int {
	if c.ProcessState == nil {
		return -1
	}
	return c.ProcessState.ExitCode()
}

// finding 6: inside an agent's sandbox (ZN_LIVE_NO_START=1) a write op reaches a running daemon and never starts one.
func TestNoStartTellsARunningDaemonAndStartsNone(t *testing.T) {
	r := newRig(t)
	code, _, errs := r.znEnv(r.dir, []string{"ZN_LIVE_NO_START=1"}, "emit", "spent", "--unit", "c1")
	if code != 3 {
		t.Fatalf("no daemon, no start: want exit 3, got %d %q", code, errs)
	}
	if _, err := os.Stat(r.dir); err == nil {
		t.Fatal("a refused start made the state directory")
	}
	r.serve(r.dir)
	code, out, errs := r.znEnv(r.dir, []string{"ZN_LIVE_NO_START=1"}, "emit", "spent", "--unit", "c1")
	if code != 0 || !strings.Contains(out, `"ok":true`) {
		t.Fatalf("a running daemon is told: got %d %q %q", code, out, errs)
	}
}
