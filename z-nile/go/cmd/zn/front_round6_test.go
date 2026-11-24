package main

import (
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// The sixth review round of f0428 step 4 (the narrow verification of round 5): each test names the item it guards.

// sq is s as one word for /bin/sh.
func sq(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

// helperLine is the shell words that run this test binary's helper test.
func helperLine(helper string) string { return sq(os.Args[0]) + " -test.run=^" + helper + "$" }

// psField is one ps(1) field of pid (tpgid, pgid, stat), or "" when the process is gone.
func psField(t *testing.T, field string, pid int) string {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, _ := exec.CommandContext(ctx, needProgram(t, "ps", "procps"), "-o", field+"=", "-p", strconv.Itoa(pid)).Output()
	return strings.TrimSpace(string(out))
}

func waitState(t *testing.T, pid int, stopped bool, within time.Duration) bool {
	deadline := time.Now().Add(within)
	for time.Now().Before(deadline) {
		if strings.HasPrefix(psField(t, "stat", pid), "T") == stopped {
			return true
		}
		time.Sleep(20 * time.Millisecond)
	}
	return false
}

// T1: zn started in the background (zn list &, or bg after Ctrl-Z) leaves the terminal with the shell's job and still
// runs the engine.
func TestZnInTheBackgroundLeavesTheTerminal(t *testing.T) {
	t.Parallel()
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd, in := underPtyLine(t, ctx, "set -m; "+helperLine("TestTtyHelper")+" & wait $!", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=where")
	defer endPty(t, dir, cmd, in)
	assertKeptTheTerminal(t, dir)
}

// T1: with zn's output a pipe (zn list | less, | fzf), the pager keeps the keyboard: the engine never becomes the
// terminal's foreground group.
func TestOutputToAPipeKeepsTheTerminal(t *testing.T) {
	t.Parallel()
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd, in := underPtyLine(t, ctx, helperLine("TestTtyHelper")+" | cat", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=where")
	defer endPty(t, dir, cmd, in)
	assertKeptTheTerminal(t, dir)
}

// T1: a terminal on zn's standard input that is not zn's controlling terminal runs the engine as with no terminal,
// instead of failing to start it (the noexec message).
func TestATerminalThatIsNotZnsOwnRunsTheEngine(t *testing.T) {
	t.Parallel()
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd, in := underPty(t, ctx, "TestTtyHelper", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=nosess")
	defer endPty(t, dir, cmd, in)
	assertKeptTheTerminal(t, dir)
}

func assertKeptTheTerminal(t *testing.T, dir string) {
	t.Helper()
	if !waitFor(t, filepath.Join(dir, "code"), 30*time.Second) {
		t.Fatalf("zn did not return (engine %s)", psState(pidIn(t, filepath.Join(dir, "engine"))))
	}
	if code, _ := os.ReadFile(filepath.Join(dir, "code")); !strings.HasPrefix(string(code), "0 ") || strings.Count(strings.TrimSpace(string(code)), " ") != 1 {
		t.Errorf("code %q, want 0 and no error", code)
	}
	where := strings.Fields(readFile(t, filepath.Join(dir, "where")))
	if len(where) != 2 || where[0] == where[1] {
		t.Errorf("the engine's group took the terminal (terminal's group, engine's group): %v", where)
	}
}

// T2, T6: Ctrl-Z on a real terminal stops the engine and zn, and the terminal goes back to zn's group (so the shell
// gets its job back); a CONT to zn's group gives the terminal to the engine again and the command goes on.
func TestCtrlZWithATerminal(t *testing.T) {
	t.Parallel()
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd, in := underPty(t, ctx, "TestTtyHelper", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=stop")
	defer endPty(t, dir, cmd, in)
	if !waitFor(t, filepath.Join(dir, "ready"), 30*time.Second) {
		t.Fatal("the engine never started")
	}
	zn, engine := pidIn(t, filepath.Join(dir, "zn")), pidIn(t, filepath.Join(dir, "engine"))
	znGroup, engineGroup := psField(t, "pgid", zn), psField(t, "pgid", engine)
	if got := psField(t, "tpgid", zn); got != engineGroup {
		t.Fatalf("while running, the terminal's group is %s, want the engine's %s", got, engineGroup)
	}
	io.WriteString(in, "\x1a")
	for _, pid := range []int{engine, zn} {
		if !waitState(t, pid, true, 10*time.Second) {
			t.Fatalf("pid %d is %q after Ctrl-Z, want stopped", pid, psState(pid))
		}
	}
	if got := psField(t, "tpgid", zn); got != znGroup {
		t.Errorf("after Ctrl-Z the terminal's group is %s, want zn's %s", got, znGroup)
	}
	syscall.Kill(-zn, syscall.SIGCONT) // fg: the shell continues zn's group
	if !waitState(t, engine, false, 10*time.Second) {
		t.Fatalf("the engine is %q after CONT", psState(engine))
	}
	if got := psField(t, "tpgid", zn); got != engineGroup {
		t.Errorf("after CONT the terminal's group is %s, want the engine's %s", got, engineGroup)
	}
	os.WriteFile(filepath.Join(dir, "go"), nil, 0o644)
	if !waitFor(t, filepath.Join(dir, "code"), 10*time.Second) {
		t.Fatalf("zn did not return after CONT (engine %s, zn %s)", psState(engine), psState(zn))
	}
	if code := readFile(t, filepath.Join(dir, "code")); strings.TrimSpace(code) != "0 fg" {
		t.Errorf("code %q, want 0 and the terminal back", code)
	}
}

// T1, T6: Ctrl-Z, then bg: the job-control shell takes the terminal back when zn's job stops and keeps it when it
// continues the job in the background, so zn never gives the terminal to the engine from the background.
func TestBgAfterCtrlZLeavesTheTerminalWithTheShell(t *testing.T) {
	t.Parallel()
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	// an interactive shell (a non-interactive one, even with set -m, never sees its job stop), with no start-up file
	inner := "echo $$ > " + sq(dir+"/shell") + "; " + helperLine("TestTtyHelper") + "; echo stopped > " + sq(dir+"/stopped") + "; bg; wait"
	cmd, in := underPtyLine(t, ctx, "exec /bin/sh -i -c "+sq(inner), "ENV=", "HISTFILE=/dev/null", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=stop")
	defer endPty(t, dir, cmd, in)
	if !waitFor(t, filepath.Join(dir, "ready"), 30*time.Second) {
		t.Fatal("the engine never started")
	}
	zn, engine, shell := pidIn(t, filepath.Join(dir, "zn")), pidIn(t, filepath.Join(dir, "engine")), pidIn(t, filepath.Join(dir, "shell"))
	io.WriteString(in, "\x1a")
	// the shell goes on to its next command only once its job (zn's group) stopped; then bg continues it at once
	if !waitFor(t, filepath.Join(dir, "stopped"), 10*time.Second) {
		t.Fatalf("zn's job never stopped (zn %s, engine %s)", psState(zn), psState(engine))
	}
	if !waitState(t, engine, false, 10*time.Second) { // the shell's bg continues zn, and zn the engine
		t.Fatalf("the engine is %q after bg (zn %s)", psState(engine), psState(zn))
	}
	if got, want := psField(t, "tpgid", shell), psField(t, "pgid", shell); got != want {
		t.Errorf("after bg the terminal's group is %s, want the shell's %s (engine's %s)", got, want, psField(t, "pgid", engine))
	}
	os.WriteFile(filepath.Join(dir, "go"), nil, 0o644)
	if !waitFor(t, filepath.Join(dir, "code"), 10*time.Second) {
		t.Fatalf("zn did not return (engine %s, zn %s)", psState(engine), psState(zn))
	}
	if code := strings.TrimSpace(readFile(t, filepath.Join(dir, "code"))); code != "0 bg" {
		t.Errorf("code %q, want 0, in the background", code)
	}
}

// T4: an engine runner that cannot start after it made itself the terminal's foreground group gives the terminal back.
func TestAnEngineThatCannotStartGivesTheTerminalBack(t *testing.T) {
	t.Parallel()
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd, in := underPty(t, ctx, "TestTtyHelper", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=nostart")
	defer endPty(t, dir, cmd, in)
	if !waitFor(t, filepath.Join(dir, "code"), 30*time.Second) {
		t.Fatal("zn did not return")
	}
	if code := readFile(t, filepath.Join(dir, "code")); !strings.HasPrefix(code, "0 fg ") || !strings.Contains(code, "could not be started") {
		t.Errorf("code %q, want not started and the terminal back", code)
	}
}

// T5: with a terminal the engine is the foreground group, and it starts with TTIN and TTOU at their defaults, even when
// zn was started with them ignored.
func TestTheEngineStartsWithTerminalSignalsAtTheirDefaults(t *testing.T) {
	t.Parallel()
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd, in := underPty(t, ctx, "TestTtyHelper", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=sigs")
	defer endPty(t, dir, cmd, in)
	if !waitFor(t, filepath.Join(dir, "code"), 30*time.Second) {
		t.Fatal("zn did not return")
	}
	if got := strings.TrimSpace(readFile(t, filepath.Join(dir, "sigs"))); got != "ttin=false ttou=false" {
		t.Errorf("the engine's terminal signals ignored: %q", got)
	}
}

// T6: a signal sent to zn while it waits for the engine's output after the engine ended (a program the engine left
// running holds it) is passed to the engine's group, not dropped.
func TestASignalAfterTheEngineEndedIsPassedOn(t *testing.T) {
	t.Parallel()
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	helper := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestLeftoverHelper$")
	helper.Env = append(os.Environ(), "ZN_LEFTOVER_HELPER="+dir)
	helper.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := helper.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if pg := pidIn(t, filepath.Join(dir, "group")); pg > 1 && pg != syscall.Getpgrp() {
			syscall.Kill(-pg, syscall.SIGKILL)
		}
		helper.Process.Kill()
		helper.Wait()
	}()
	if !waitFor(t, filepath.Join(dir, "ready"), 20*time.Second) {
		t.Fatal("the engine never ended")
	}
	helper.Process.Signal(syscall.SIGTERM)
	if !waitFor(t, filepath.Join(dir, "term"), 5*time.Second) {
		t.Error("the TERM sent to zn after the engine ended never reached what the engine left running")
	}
}

// TestLeftoverHelper is the zn TestASignalAfterTheEngineEndedIsPassedOn signals: its engine ends at once and leaves a
// program running that holds its output, and that says when the engine's runner is gone.
func TestLeftoverHelper(t *testing.T) {
	dir := os.Getenv("ZN_LEFTOVER_HELPER")
	if dir == "" {
		t.Skip("run by TestASignalAfterTheEngineEndedIsPassedOn")
	}
	p := filepath.Join(dir, "engine.sh")
	leftover := "trap 'echo got > " + sq(dir+"/term") + "; exit 0' TERM; while kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.02; done; " +
		"echo ready > " + sq(dir+"/ready") + "; while :; do /bin/sleep 0.05; done"
	os.WriteFile(p, []byte("#!/bin/sh\nps -o pgid= -p $$ > "+sq(dir+"/group")+"\n/bin/sh -c "+sq(leftover)+" leftover $PPID &\nexit 0\n"), 0o755)
	runChild(p, []string{p}, []string{"PATH=/usr/bin:/bin"}, io.Discard, io.Discard)
}

// T3: with no terminal, a login the tracker's remote asks for (ssh's passphrase prompt, which prompts again and again
// on a terminal it cannot read) fails at once, with what to do, in the engine's fetch and push and in zn's own fetch;
// nothing is left running. One fixture for both; zn's own git meets the decoy folder's stub (TestMain).
func TestALoginThatCannotBeAskedForFailsFast(t *testing.T) {
	t.Parallel()
	f, hostDir, _, _ := hostWithEngine(t)
	f.step(t, "list")
	pids := stubSSH(t, f)
	engine := f.d.child
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) {
		gitOut(t, filepath.Join(hostDir, ".tracker"), "remote", "set-url", "origin", "git@example.invalid:o/tracker.git")
		return engine(path, argv, env, out, errw)
	}
	code, errOut := runWithin(t, f, pids, []string{"new", "issue", "f", "login", "--desc", "x"})
	engineSaid := false // the engine's message (git's words span lines) up to zn's next line
	if i := strings.Index(errOut, "push rejected after"); i >= 0 {
		said, _, _ := strings.Cut(errOut[i:], "\nzn:")
		engineSaid = strings.Contains(said, "Permission denied") && strings.Contains(said, "could not be asked for here")
	}
	if code == 0 || !engineSaid {
		t.Errorf("the engine: exit %d, its words lack what to do: %s", code, errOut)
	}
	// zn's own fetch (the origin is the ssh one now): not fatal to list, which works from main as last fetched, but
	// its words say what to do
	f.d.child = engine
	code, errOut = runWithin(t, f, pids, []string{"list"})
	if !strings.Contains(errOut, "could not be asked for here") || !strings.Contains(errOut, "ssh agent") {
		t.Errorf("zn's own fetch: exit %d: %s", code, errOut)
	}
	assertStubsGone(t, pids)
}

// sshStub is an ssh that does what ssh does for a key with a passphrase: with SSH_ASKPASS_REQUIRE=force it asks
// SSH_ASKPASS, else it prompts on /dev/tty and, when that cannot be read, prompts again (readpassphrase). It appends
// its pid to pids. TestMain puts one in the decoy folder first on the process's PATH (zn's own git), so no test ever
// runs a real ssh.
func sshStub(pids string) string {
	return "#!/bin/sh\necho $$ >> " + sq(pids) + "\n" +
		"if [ \"$SSH_ASKPASS_REQUIRE\" = force ] && [ -n \"$SSH_ASKPASS\" ]; then\n" +
		"  \"$SSH_ASKPASS\" \"Enter passphrase for key '/k': \" </dev/null >/dev/null 2>&1 || { echo 'Permission denied (publickey).' >&2; exit 255; }\nfi\n" +
		"while :; do\n  printf \"Enter passphrase for key '/k': \" >/dev/tty 2>/dev/null\n  read -r p </dev/tty 2>/dev/null && break\n  /bin/sleep 0.2\ndone\n" +
		"echo 'Permission denied (publickey).' >&2\nexit 255\n"
}

// decoySSHPids is where the decoy folder's stub ssh records its pids (TestMain).
var decoySSHPids string

// stubSSH puts the stub ssh first on the PATH zn passes the engine and returns the files the stubs record their pids
// in (the engine's, then zn's own: the decoy's).
func stubSSH(t *testing.T, f *fake) []string {
	t.Helper()
	stubs := resolved(t)
	pids := filepath.Join(stubs, "pids")
	os.WriteFile(filepath.Join(stubs, "ssh"), []byte(sshStub(pids)), 0o755)
	for i, e := range f.d.env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			f.d.env[i] = "PATH=" + stubs + ":" + v
		}
	}
	return []string{pids, decoySSHPids}
}

// runWithin runs zn bounded: on the bound it kills the stub ssh processes (so the git waiting on them ends) and fails.
func runWithin(t *testing.T, f *fake, pids []string, args []string) (int, string) {
	t.Helper()
	f.out.Reset()
	f.errOut.Reset()
	done := make(chan int, 1)
	go func() { done <- run(args, f.d) }()
	select {
	case code := <-done:
		return code, f.errOut.String()
	case <-time.After(30 * time.Second):
		for _, p := range pids {
			b, _ := os.ReadFile(p)
			for _, l := range strings.Fields(string(b)) {
				if pid, _ := strconv.Atoi(l); pid > 1 {
					killPid(pid)
				}
			}
		}
		<-done
		t.Fatalf("zn %v did not end within 30 s: a prompt no one can answer kept it waiting", args)
		return 0, ""
	}
}

func assertStubsGone(t *testing.T, pids []string) {
	t.Helper()
	ran := 0
	for _, p := range pids {
		b, _ := os.ReadFile(p)
		for _, l := range strings.Fields(string(b)) {
			ran++
			if pid, _ := strconv.Atoi(l); pid > 1 && !gone(pid) {
				killPid(pid)
				t.Errorf("the stub ssh %d was left running", pid)
			}
		}
	}
	if ran == 0 {
		t.Error("no stub ssh ran: the test did not reach a login")
	}
}
