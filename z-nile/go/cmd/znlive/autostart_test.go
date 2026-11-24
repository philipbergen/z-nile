package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

// stopAutostarted ends the daemon an op started, and waits for its pid to go.
func (r *rig) stopAutostarted(dir string) {
	r.t.Helper()
	code, out, _ := r.zn(dir, "status")
	if code != 0 {
		return
	}
	pid := int(parse(r.t, out)["pid"].(float64))
	r.zn(dir, "shutdown")
	for i := 0; i < 300 && syscall.Kill(pid, 0) == nil; i++ {
		time.Sleep(10 * time.Millisecond)
	}
	if syscall.Kill(pid, 0) == nil {
		syscall.Kill(pid, syscall.SIGKILL)
		r.t.Errorf("daemon %d did not shut down", pid)
	}
}

// AC17: a write op with no daemon starts one (in its own session, its log in daemon.log); a read op starts none.
func TestAutostartWriteOnlyAndDetached(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	for _, op := range []string{"status", "workers", "claims", "wait", "events", "poke", "shutdown"} {
		args := []string{op}
		if op == "wait" {
			args = append(args, "--worker", "w")
		}
		if code, _, _ := r.zn(r.dir, args...); code != 3 {
			t.Fatalf("%s with no daemon: exit %d, want 3", op, code)
		}
	}
	if _, err := os.Stat(filepath.Join(r.dir, "socket")); err == nil {
		t.Fatal("a read op started a daemon")
	}
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	code, out, errb := r.znEnv(r.dir, []string{"ZN_BOUNDED_DEADLINE=1", "ZN_MEASURE_KIND=x"}, "register", "--cli", "t", "--pid",
		fmt.Sprint(os.Getpid()), "--idle-exit", "30s")
	if code != 0 {
		t.Fatalf("register: %d %s %s", code, out, errb)
	}
	_, out, _ = r.zn(r.dir, "status")
	pid := int(parse(t, out)["pid"].(float64))
	if sid, _ := getsid(pid); sid != pid {
		t.Fatalf("the daemon's session is %d, want its own (%d)", sid, pid)
	}
	if env := procEnv(t, pid); strings.Contains(env, "ZN_BOUNDED_DEADLINE") || strings.Contains(env, "ZN_MEASURE_KIND") {
		t.Fatalf("the daemon carries a bounded-runner marker: %s", env)
	}
	if b, err := os.ReadFile(filepath.Join(r.dir, "daemon.log")); err != nil || !strings.Contains(string(b), "serving") {
		t.Fatalf("daemon.log: %v %q", err, b)
	}
}

// Rule 3: ten clients writing at once against no daemon end with exactly one daemon and ten replies.
func TestAutostartRaceOneDaemon(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	var wg sync.WaitGroup
	codes := make([]int, 10)
	for i := range codes {
		wg.Add(1)
		go func() { // owner: this test; ends with its op
			defer wg.Done()
			codes[i], _, _ = r.zn(r.dir, "register", "--worker", fmt.Sprintf("w%d", i), "--cli", "t", "--pid", fmt.Sprint(os.Getpid()), "--idle-exit", "30s")
		}()
	}
	wg.Wait()
	for i, c := range codes {
		if c != 0 {
			t.Fatalf("client %d exited %d", i, c)
		}
	}
	_, out, _ := r.zn(r.dir, "workers")
	if n := len(parse(t, out)["workers"].([]any)); n != 10 {
		t.Fatalf("%d workers registered, want 10", n)
	}
	if b, _ := os.ReadFile(filepath.Join(r.dir, "daemon.log")); strings.Count(string(b), "serving") != 1 {
		t.Fatalf("more than one daemon started: %q", b)
	}
}

// The daemon started by an op idle-exits on the flag the op passed.
func TestAutostartPassesIdleExit(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	if code, _, e := r.zn(r.dir, "register", "--worker", "w", "--cli", "t", "--pid", fmt.Sprint(os.Getpid()), "--idle-exit", "400ms"); code != 0 {
		t.Fatalf("register: %d %s", code, e)
	}
	r.zn(r.dir, "gone", "--worker", "w")
	for i := 0; i < 300; i++ {
		if code, _, _ := r.zn(r.dir, "status"); code == 3 {
			return
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatal("the daemon did not idle-exit")
}

// procEnv is the environment of a process of this user, from ps.
func procEnv(t *testing.T, pid int) string {
	t.Helper()
	out, err := exec.Command("ps", "-E", "-ww", "-o", "command=", "-p", fmt.Sprint(pid)).Output()
	if err != nil {
		t.Skipf("ps cannot show the environment: %v", err)
	}
	return string(out)
}
