package main

import (
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

// starter runs a client the way a worker in some other shell does: its own folder, its own TMPDIR, and a busy environment.
func starter(t *testing.T, cwd, tmp string, extra []string, args ...string) (int, string, string) {
	t.Helper()
	cmd := exec.Command(binary, args...)
	cmd.Dir = cwd
	cmd.Env = append([]string{"PATH=" + os.Getenv("PATH"), "HOME=" + os.Getenv("HOME"), "TMPDIR=" + tmp, "CLAUDECODE=1",
		"ZN_WORKER=x", "CLAUDE_CODE_SESSION_ID=y", "ZN_BOUNDED_DEADLINE=1", "ZN_LIVE_DIR="}, extra...)
	var out, errb bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errb
	err := cmd.Run()
	code := 0
	if ee, ok := err.(*exec.ExitError); ok {
		code = ee.ExitCode()
	} else if err != nil {
		t.Fatal(err)
	}
	return code, out.String(), errb.String()
}

func daemonPid(t *testing.T, r *rig, dir string) int {
	t.Helper()
	code, out, _ := r.zn(dir, "status")
	if code != 0 {
		t.Fatalf("status exited %d", code)
	}
	return int(parse(t, out)["pid"].(float64))
}

func waitGone(t *testing.T, pid int) {
	t.Helper()
	for i := 0; i < 500 && syscall.Kill(pid, 0) == nil; i++ {
		time.Sleep(10 * time.Millisecond)
	}
	if syscall.Kill(pid, 0) == nil {
		syscall.Kill(pid, syscall.SIGKILL)
		t.Errorf("daemon %d did not exit", pid)
	}
}

// F1: a daemon started from a folder and a TMPDIR that are then deleted keeps working for everyone else, under the default
// socket rule (forced on a throwaway state directory), carries no environment of its starter, and works from "/".
func TestDaemonOutlivesItsStartersFolders(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	cwd, tmp := filepath.Join(r.tmp, "cwd"), filepath.Join(r.tmp, "starter-tmp")
	os.Mkdir(cwd, 0o755)
	os.Mkdir(tmp, 0o755)
	me := fmt.Sprint(os.Getpid())
	force := []string{"ZN_LIVE_SOCKDIR=stable"}
	code, out, errb := starter(t, cwd, tmp, force, "register", "--worker", "a", "--cli", "t", "--pid", me, "--dir", r.dir,
		"--idle-exit", "60s")
	if code != 0 {
		t.Fatalf("register: %d %s %s", code, out, errb)
	}
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	pid := daemonPid(t, r, r.dir)
	// the daemon holds nothing of its starter's environment
	log, _ := os.ReadFile(filepath.Join(r.dir, "daemon.log"))
	var names string
	for _, l := range strings.Split(string(log), "\n") {
		if _, rest, ok := strings.Cut(l, "environment names ("); ok {
			_, names, _ = strings.Cut(rest, "): ")
		}
	}
	if names == "" {
		t.Fatalf("daemon.log names no environment: %q", log)
	}
	for _, n := range strings.Split(names, ",") {
		switch {
		case n == "PATH" || n == "HOME" || n == "USER" || n == "LOGNAME" || n == "LANG" || strings.HasPrefix(n, "LC_"):
		default:
			t.Errorf("the daemon holds %s", n)
		}
	}
	// its working folder is "/" and its socket is not under the starter's TMPDIR
	if cwdOf := procCwd(t, pid); cwdOf != "" && cwdOf != "/" {
		t.Errorf("the daemon's working folder is %s, want /", cwdOf)
	}
	ptr, _ := os.ReadFile(filepath.Join(r.dir, "socket"))
	if strings.Contains(string(ptr), tmp) || strings.Contains(string(ptr), r.tmp) {
		t.Fatalf("the socket %s is under the starter's TMPDIR", ptr)
	}
	// the starter's folders go away, as a jail's do; every other process still reaches the daemon
	os.RemoveAll(cwd)
	os.RemoveAll(tmp)
	other := filepath.Join(r.tmp, "other")
	os.Mkdir(other, 0o755)
	if code, out, errb := starter(t, other, other, force, "workers", "--dir", r.dir); code != 0 || !strings.Contains(out, `"a"`) {
		t.Fatalf("read after the starter's folders went away: %d %s %s", code, out, errb)
	}
	if code, out, errb := starter(t, other, other, force, "register", "--worker", "b", "--cli", "t", "--pid", me, "--dir", r.dir); code != 0 {
		t.Fatalf("write after the starter's folders went away: %d %s %s", code, out, errb)
	}
	if got := daemonPid(t, r, r.dir); got != pid {
		t.Fatalf("a second daemon started: %d then %d", pid, got)
	}
}

// procCwd is a process's working folder, from lsof; "" when it cannot be asked.
func procCwd(t *testing.T, pid int) string {
	out, err := exec.Command("lsof", "-a", "-d", "cwd", "-Fn", "-p", fmt.Sprint(pid)).Output()
	if err != nil {
		return ""
	}
	for _, l := range strings.Split(string(out), "\n") {
		if strings.HasPrefix(l, "n") {
			return l[1:]
		}
	}
	return ""
}

// F1c: a daemon whose socket file, or whose state directory, is gone exits at its next check, so the next write op starts one
// that can be reached.
func TestDaemonExitsWhenUnreachable(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	me := fmt.Sprint(os.Getpid())
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	if code, _, e := r.zn(r.dir, "register", "--worker", "w", "--cli", "t", "--pid", me, "--idle-exit", "60s", "--check-every", "200ms"); code != 0 {
		t.Fatal(e)
	}
	pid := daemonPid(t, r, r.dir)
	ptr, _ := os.ReadFile(filepath.Join(r.dir, "socket"))
	os.Remove(strings.TrimSpace(string(ptr)))
	waitGone(t, pid)
	if code, _, e := r.zn(r.dir, "register", "--worker", "w", "--cli", "t", "--pid", me, "--idle-exit", "60s", "--check-every", "200ms"); code != 0 {
		t.Fatalf("the next write did not start a daemon: %s", e)
	}
	pid2 := daemonPid(t, r, r.dir)
	if pid2 == pid {
		t.Fatal("the old daemon still answers")
	}
	// the state directory removed (a folder swept away): the daemon exits too
	os.RemoveAll(r.dir)
	waitGone(t, pid2)
	if code, _, e := r.zn(r.dir, "register", "--worker", "w", "--cli", "t", "--pid", me, "--idle-exit", "60s"); code != 0 {
		t.Fatalf("after the state directory went: %s", e)
	}
}

// F4: a write op right after a shutdown, while the old daemon is still draining, starts a daemon and succeeds: 50 times.
func TestWriteRightAfterShutdown(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	me := fmt.Sprint(os.Getpid())
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	for i := 0; i < 50; i++ {
		if code, _, e := r.zn(r.dir, "register", "--worker", "w", "--cli", "t", "--pid", me, "--idle-exit", "60s"); code != 0 {
			t.Fatalf("iteration %d: register exited %d: %s", i, code, e)
		}
		r.zn(r.dir, "shutdown")
	}
}

// F6: the timing flags configure the shared daemon, so the default state directory refuses them; a named one takes them.
func TestTimingFlagsRefusedForTheDefaultDirectory(t *testing.T) {
	t.Parallel()
	r := newRig(t)
	me := fmt.Sprint(os.Getpid())
	t.Cleanup(func() { r.stopAutostarted(r.dir) })
	env := []string{"ZN_LIVE_DIR=" + r.dir, "ZN_LIVE_DIR_IS_DEFAULT=1", "ZN_LIVE_SOCKDIR=" + r.tmp}
	code, out, errb := starter(t, r.tmp, r.tmp, env, "register", "--worker", "w", "--cli", "t", "--pid", me, "--idle-exit", "5s")
	if code != 2 || out != "" || !strings.Contains(errb, "for tests") || !strings.Contains(errb, "--idle-exit") {
		t.Fatalf("default directory with a timing flag: %d %q %q", code, out, errb)
	}
	if _, err := os.Stat(filepath.Join(r.dir, "socket")); err == nil {
		t.Fatal("a refused op started a daemon")
	}
	// without the flag the default directory is served, with the daemon's own limits
	code, out, errb = starter(t, r.tmp, r.tmp, env, "register", "--worker", "w", "--cli", "t", "--pid", me)
	if code != 0 {
		t.Fatalf("default directory, no flag: %d %s %s", code, out, errb)
	}
	log, _ := os.ReadFile(filepath.Join(r.dir, "daemon.log"))
	if strings.Contains(string(log), "idle for") {
		t.Fatalf("%s", log)
	}
	// a named directory takes them: the other tests rely on it (--idle-exit 400ms in TestAutostartPassesIdleExit)
}
