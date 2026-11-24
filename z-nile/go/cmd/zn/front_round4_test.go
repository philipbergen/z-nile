package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// The fourth review round of f0428 step 4 (review-003.md): each test names the finding it guards.

// waitFor polls for a marker file, bounded; it never sleeps for a fixed time to let something happen.
func waitFor(t *testing.T, p string, within time.Duration) bool {
	t.Helper()
	deadline := time.Now().Add(within)
	for time.Now().Before(deadline) {
		if b, err := os.ReadFile(p); err == nil && strings.HasSuffix(string(b), "\n") {
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	return false
}

func pidIn(t *testing.T, p string) int {
	t.Helper()
	b, _ := os.ReadFile(p)
	pid, _ := strconv.Atoi(strings.TrimSpace(string(b)))
	return pid
}

func gone(pid int) bool {
	for i := 0; i < 100; i++ {
		if syscall.Kill(pid, 0) != nil {
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	return false
}

// script writes an executable shell script and returns its path.
func script(t *testing.T, body string) string {
	t.Helper()
	p := filepath.Join(resolved(t), "engine.sh")
	if err := os.WriteFile(p, []byte("#!/bin/sh\n"+body), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

type runResult struct {
	code int
	err  error
}

// runBounded runs runChild in the background and waits for it, bounded; on the bound it kills the group whose leader's
// pid the script wrote to group (the test then fails instead of hanging).
func runBounded(t *testing.T, path string, out, errw io.Writer, group string, within time.Duration, during func()) runResult {
	t.Helper()
	done := make(chan runResult, 1)
	go func() {
		code, err := runChild(path, []string{path}, []string{"PATH=/usr/bin:/bin"}, out, errw)
		done <- runResult{code, err}
	}()
	if during != nil {
		during()
	}
	select {
	case r := <-done:
		return r
	case <-time.After(within):
		if pid := pidIn(t, group); pid > 1 { // the engine's group, never the test's own
			if pg, err := syscall.Getpgid(pid); err == nil && pg > 1 && pg != syscall.Getpgrp() {
				syscall.Kill(-pg, syscall.SIGKILL)
			}
			killPid(pid)
		}
		t.Fatalf("runChild did not return within %s", within)
		return runResult{}
	}
}

// P4: the real child runner passes the engine's exit code and zn's standard input through.
func TestRunChildPassesTheExitCodeAndStdin(t *testing.T) {
	childStdin = strings.NewReader("hello\n")
	defer func() { childStdin = os.Stdin }()
	var out bytes.Buffer
	dir := resolved(t)
	p := script(t, "echo $$ > '"+dir+"/group'\nread line\necho \"got:$line\"\nexit 3\n")
	r := runBounded(t, p, &out, io.Discard, filepath.Join(dir, "group"), 10*time.Second, nil)
	if r.err != nil || r.code != 3 || out.String() != "got:hello\n" {
		t.Errorf("code %d, err %v, out %q", r.code, r.err, out.String())
	}
}

// P3, P4: INT, QUIT, TERM and HUP sent to zn reach the engine's whole process group, its children included.
func TestRunChildForwardsSignalsToTheGroup(t *testing.T) {
	for _, sig := range []syscall.Signal{syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP, syscall.SIGQUIT} {
		t.Run(sig.String(), func(t *testing.T) {
			dir := resolved(t)
			p := script(t, "echo $$ > '"+dir+"/group'\ntrap 'echo got > \""+dir+"/got\"; exit 0' "+strconv.Itoa(int(sig))+
				"\n/usr/bin/perl -e '$SIG{INT}=$SIG{QUIT}=\"DEFAULT\"; open(F, \">\", \""+dir+"/child.tmp\"); print F \"$$\\n\"; close F; rename(\""+dir+"/child.tmp\", \""+dir+"/child\"); exec \"/bin/sleep\", \"30\"' &\n"+
				"until [ -f '"+dir+"/child' ]; do /bin/sleep 0.02; done\necho ready > '"+dir+"/ready'\nwait\n")
			r := runBounded(t, p, io.Discard, io.Discard, filepath.Join(dir, "group"), 15*time.Second, func() {
				if !waitFor(t, filepath.Join(dir, "ready"), 10*time.Second) {
					t.Error("the engine never started")
					return
				}
				syscall.Kill(os.Getpid(), sig) // as a terminal or a supervisor sends it to zn
			})
			if _, err := os.Stat(filepath.Join(dir, "got")); err != nil {
				t.Errorf("%s did not reach the engine (code %d)", sig, r.code)
			}
			if child := pidIn(t, filepath.Join(dir, "child")); child <= 0 || !gone(child) {
				killPid(child)
				t.Errorf("the engine's child outlived %s", sig)
			}
		})
	}
}

// P4: an engine ended by a signal is reported as 128+n, as a shell reports it: by its own kill (the engine's exit
// status) and by a TERM zn forwarded to the whole group (zn's runner itself is then signalled). The script never sends a
// signal to a group: a runner that left it in the test's group would end the test with it.
func TestRunChildReportsASignalAs128PlusN(t *testing.T) {
	dir := resolved(t)
	p := script(t, "echo $$ > '"+dir+"/group'\nkill -KILL $$\n")
	r := runBounded(t, p, io.Discard, io.Discard, filepath.Join(dir, "group"), 10*time.Second, nil)
	if r.err != nil || r.code != 128+9 {
		t.Errorf("killed by itself: code %d, err %v, want 137", r.code, r.err)
	}
	dir = resolved(t)
	p = script(t, "echo $$ > '"+dir+"/group'\necho ready > '"+dir+"/ready'\nwhile :; do /bin/sleep 0.05; done\n")
	r = runBounded(t, p, io.Discard, io.Discard, filepath.Join(dir, "group"), 15*time.Second, func() {
		if waitFor(t, filepath.Join(dir, "ready"), 10*time.Second) {
			syscall.Kill(os.Getpid(), syscall.SIGTERM)
		}
	})
	if r.err != nil || r.code != 128+15 {
		t.Errorf("ended by a forwarded TERM: code %d, err %v, want 143", r.code, r.err)
	}
}

// P3: when zn's standard output breaks (zn list | head -1), the engine ends too and runChild returns.
func TestABrokenStdoutEndsTheEngine(t *testing.T) {
	dir := resolved(t)
	p := script(t, "echo $$ > '"+dir+"/group'\nwhile :; do echo line || exit 9; /bin/sleep 0.05; done\n")
	r := runBounded(t, p, brokenWriter{}, io.Discard, filepath.Join(dir, "group"), 15*time.Second, nil)
	if r.code == 0 {
		t.Errorf("the engine went on after its output broke: code %d, err %v", r.code, r.err)
	}
}

type brokenWriter struct{}

func (brokenWriter) Write(p []byte) (int, error) { return 0, syscall.EPIPE }

// P3: nohup zn: a HUP ignored when zn started is ignored for the engine too, never forwarded. The zn is a helper
// process that ignores HUP from its start, as nohup leaves it (an ignored signal cannot be put back in this process).
func TestAnIgnoredHupIsRespected(t *testing.T) {
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	helper := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestHupHelper$")
	helper.Env = append(os.Environ(), "ZN_HUP_HELPER="+dir)
	if err := helper.Start(); err != nil {
		t.Fatal(err)
	}
	defer helper.Wait()
	if !waitFor(t, filepath.Join(dir, "ready"), 20*time.Second) {
		helper.Process.Kill()
		t.Fatal("the helper's engine never started")
	}
	helper.Process.Signal(syscall.SIGHUP)  // a forwarded HUP would be taken before the TERM that follows
	helper.Process.Signal(syscall.SIGTERM) // forwarded: it ends the engine, and so the helper
	if !waitFor(t, filepath.Join(dir, "done"), 20*time.Second) {
		helper.Process.Kill()
		t.Fatal("the helper's engine did not end on TERM")
	}
	if _, err := os.Stat(filepath.Join(dir, "hup")); err == nil {
		t.Error("an ignored HUP was forwarded to the engine")
	}
}

// TestHupHelper is the nohup zn of TestAnIgnoredHupIsRespected: it runs only with the variable set.
func TestHupHelper(t *testing.T) {
	dir := os.Getenv("ZN_HUP_HELPER")
	if dir == "" {
		t.Skip("run by TestAnIgnoredHupIsRespected")
	}
	signal.Ignore(syscall.SIGHUP)
	p := filepath.Join(dir, "engine.sh")
	os.WriteFile(p, []byte("#!/bin/sh\ntrap 'echo hup > \""+dir+"/hup\"' HUP\ntrap 'echo done > \""+dir+"/done\"; exit 0' TERM\necho ready > '"+dir+"/ready'\nwhile :; do /bin/sleep 0.05; done\n"), 0o755)
	runChild(p, []string{p}, []string{"PATH=/usr/bin:/bin"}, io.Discard, io.Discard)
}

// P3: the engine dies with zn, even when zn is killed outright: its whole group is ended by the lifeline.
func TestTheEngineDiesWithZn(t *testing.T) {
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	helper := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestRunChildHelper$")
	helper.Env = append(os.Environ(), "ZN_RUNCHILD_HELPER="+dir)
	if err := helper.Start(); err != nil {
		t.Fatal(err)
	}
	if !waitFor(t, filepath.Join(dir, "child"), 20*time.Second) {
		helper.Process.Kill()
		helper.Wait()
		t.Fatal("the helper never started its engine")
	}
	helper.Process.Kill()
	helper.Wait()
	for _, f := range []string{"engine", "child"} {
		if pid := pidIn(t, filepath.Join(dir, f)); pid <= 0 || !gone(pid) {
			killPid(pid)
			t.Errorf("the %s (pid %d) outlived zn", f, pid)
		}
	}
}

// TestRunChildHelper is the zn TestTheEngineDiesWithZn kills: it runs only with the variable set.
func TestRunChildHelper(t *testing.T) {
	dir := os.Getenv("ZN_RUNCHILD_HELPER")
	if dir == "" {
		t.Skip("run by TestTheEngineDiesWithZn")
	}
	p := filepath.Join(dir, "engine.sh")
	os.WriteFile(p, []byte("#!/bin/sh\necho $$ > '"+dir+"/engine'\n/bin/sleep 30 &\necho $! > '"+dir+"/child'\nwait\n"), 0o755)
	runChild(p, []string{p}, []string{"PATH=/usr/bin:/bin"}, io.Discard, io.Discard)
}

// P4, P7: the terminal filter escapes every control (C0 but newline and tab, DEL, C1, invalid and over-long bytes, bidi
// and line separators), keeps a sequence split across two writes whole, and escapes a tail still held at Flush.
func TestTheTerminalFilter(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		writes []string
		want   string
	}{
		{[]string{"plain text\twith tab\nand newline\n"}, "plain text\twith tab\nand newline\n"},
		{[]string{"a\x1b[2Jb\x07c\x01\r"}, `a\x1b[2Jb\x07c\x01\x0d`},
		{[]string{"del\x7f"}, `del\x7f`},
		{[]string{"c1 \u009b31m \u0085"}, `c1 \u009b31m \u0085`},
		{[]string{"bad \xff and over-long \xc0\x80"}, `bad \xff and over-long \xc0\x80`},
		{[]string{"caf\xc3", "\xa9 ok"}, "café ok"},
		{[]string{"split c1 \xc2", "\x9b31m"}, `split c1 \u009b31m`},
		{[]string{"bidi \u202eevil\u2069 \u2028"}, `bidi \u202eevil\u2069 \u2028`},
		{[]string{"joiner \U0001F468\u200d\U0001F469"}, "joiner \U0001F468\u200d\U0001F469"},
		{[]string{"tail \xe2\x82"}, `tail \xe2\x82`},
	} {
		var b bytes.Buffer
		f := newTerminalFilter(&b)
		for _, w := range c.writes {
			if n, err := f.Write([]byte(w)); err != nil || n != len(w) {
				t.Errorf("Write(%q) = %d, %v", w, n, err)
			}
		}
		f.Flush()
		if b.String() != c.want {
			t.Errorf("%q: got %q, want %q", c.writes, b.String(), c.want)
		}
	}
}

// P4: what the engine prints on stderr (list and audit name tracker files there) is filtered as stdout is.
func TestTheEnginesStderrIsFiltered(t *testing.T) {
	t.Parallel()
	f, _, _, _ := hostWithEngine(t)
	f.step(t, "list")
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) {
		io.WriteString(out, "out \x1b[2J\n")
		io.WriteString(errw, "error no-slug up/.tracker/issues/f0009\x1b]0;owned\x07: x\n")
		return 0, nil
	}
	f.errOut.Reset()
	run([]string{"list"}, f.d)
	if strings.ContainsAny(f.out.String()+f.errOut.String(), "\x1b\x07") {
		t.Errorf("raw control bytes: %q %q", f.out.String(), f.errOut.String())
	}
	if !strings.Contains(f.errOut.String(), `f0009\x1b]0;owned\x07`) {
		t.Errorf("stderr is not shown escaped: %q", f.errOut.String())
	}
}

// P4, N1: status remembers the claim from the commit it published, not from the worktree's file (which still holds
// the old stamp while the front door has not moved the worktree).
func TestStatusRemembersThePublishedClaim(t *testing.T) {
	t.Parallel()
	f, hostDir, bare, _ := hostWithEngine(t)
	f.step(t, "new", "issue", "f", "claimed", "--desc", "x")
	other := filepath.Join(resolved(t), "edit")
	gitOut(t, filepath.Dir(other), "clone", "-q", bare, other)
	doc := filepath.Join(other, "up", ".tracker", "issues", "f0001", "f0001.md")
	b, _ := os.ReadFile(doc)
	os.WriteFile(doc, []byte(strings.Replace(string(b), "idea: unchallenged", "idea: challenged", 1)), 0o644)
	os.WriteFile(filepath.Join(filepath.Dir(doc), "idea-review-001.md"), []byte("# Idea review 001\n\nVerdict: approve\n"), 0o644)
	gitOut(t, other, "add", "-A")
	gitOut(t, other, "commit", "-q", "-m", "the idea was challenged")
	gitOut(t, other, "push", "-q", "origin", "main")
	f.step(t, "status", "f0001", "preparing")
	claim := filepath.Join(hostDir, ".tracker", ".worktree", "zn", ".cache", "tracker-claim-f0001")
	got, err := os.ReadFile(claim)
	if err != nil || !strings.HasPrefix(string(got), "preparing") {
		t.Errorf("the remembered claim is %q (%v), want the published preparing stamp", got, err)
	}
}

// P8(b): in a host, status <id> prepared is refused before the engine starts (it edits tracked files in the standing
// worktree), with what to do instead.
func TestStatusPreparedIsRefusedInAHost(t *testing.T) {
	t.Parallel()
	f, _, _, _ := hostWithEngine(t)
	f.step(t, "new", "issue", "f", "x", "--desc", "x")
	starts := 0
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) { starts++; return 0, nil }
	f.errOut.Reset()
	if code := run([]string{"status", "f0001", "prepared"}, f.d); code != exitRefused || starts != 0 {
		t.Errorf("exit %d, %d starts", code, starts)
	}
	if !strings.Contains(f.errOut.String(), "prepared") || !strings.Contains(f.errOut.String(), "not yet available in a host repository") {
		t.Errorf("stderr %q", f.errOut.String())
	}
	if code := run([]string{"status", "f0001"}, f.d); code != 0 || starts != 1 {
		t.Errorf("status f0001: exit %d, %d starts", code, starts)
	}
}

// P8(c): status with the tracker unreachable says why without naming the remote.
func TestOfflineStatusNamesNoRemote(t *testing.T) {
	t.Parallel()
	f, _, bare, _ := hostWithEngine(t)
	f.step(t, "new", "issue", "f", "offline", "--desc", "x")
	if err := os.Rename(bare, bare+".away"); err != nil {
		t.Fatal(err)
	}
	f.out.Reset()
	f.errOut.Reset()
	run([]string{"status", "f0001"}, f.d)
	all := f.out.String() + f.errOut.String()
	if strings.Contains(all, bare) || strings.Contains(all, filepath.Base(bare)) {
		t.Errorf("the remote's address is printed: %q", all)
	}
}

// P11: a front door with no child runner refuses rather than falling back to exec (which would drop the lock, the
// filter and the refresh).
func TestNoChildRunnerIsRefused(t *testing.T) {
	t.Parallel()
	f, _, _, _ := hostWithEngine(t)
	f.step(t, "list")
	execs := 0
	f.d.child = nil
	f.d.exec = func(path string, argv, env []string) error { execs++; return nil }
	f.errOut.Reset()
	if code := run([]string{"list"}, f.d); code != exitRefused || execs != 0 {
		t.Errorf("exit %d, %d execs: %s", code, execs, f.errOut.String())
	}
}

// P11: an engine that ended with an error other than its exit status is not reported as a noexec mount, and the
// refresh still runs.
func TestAnEngineErrorStillRefreshes(t *testing.T) {
	t.Parallel()
	f, hostDir, bare, _ := hostWithEngine(t)
	f.step(t, "list")
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) {
		pushToTracker(t, bare, map[string]*string{"later.txt": text("x")}, nil)
		gitOut(t, filepath.Join(hostDir, ".tracker"), "fetch", "-q", "origin", "main") // as the engine's publish fetches
		return 0, errors.New("wait: input/output error")
	}
	f.errOut.Reset()
	if code := run([]string{"list"}, f.d); code != 1 { // round 5 (Q7): it ran and failed, so not 0 even at status 0
		t.Errorf("exit %d, want 1", code)
	}
	if strings.Contains(f.errOut.String(), "noexec") {
		t.Errorf("reported as a noexec mount: %q", f.errOut.String())
	}
	if !strings.Contains(f.errOut.String(), "moved the standing worktree") {
		t.Errorf("the refresh did not run: %q", f.errOut.String())
	}
}

// killPid ends one process by its pid, and never a group: kill(0) or kill(-1) would end the test's own group or every
// process of the user.
func killPid(pid int) {
	if pid > 1 {
		syscall.Kill(pid, syscall.SIGKILL)
	}
}
