package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// The fifth review round of f0428 step 4 (review-004.md): each test names the finding it guards.

// underPty runs this test binary's helper test under script(1), so the helper has a terminal: a pseudo-terminal whose
// input the test writes through script's standard input. The helper replaces the shell, so it leads the terminal's
// session and its foreground group. Bounded by ctx.
func underPty(t *testing.T, ctx context.Context, helper string, env ...string) (*exec.Cmd, io.WriteCloser) {
	t.Helper()
	return underPtyLine(t, ctx, "exec "+helperLine(helper), env...)
}

// underPtyLine runs a /bin/sh command line under script(1): the BSD form (macOS, the BSDs) or util-linux's (Linux).
func underPtyLine(t *testing.T, ctx context.Context, line string, env ...string) (*exec.Cmd, io.WriteCloser) {
	t.Helper()
	bin := needProgram(t, "script", "util-linux")
	var cmd *exec.Cmd
	if runtime.GOOS == "linux" {
		cmd = exec.CommandContext(ctx, bin, "-qec", line, "/dev/null")
	} else {
		cmd = exec.CommandContext(ctx, bin, "-q", "/dev/null", "/bin/sh", "-c", line)
	}
	cmd.Env = append(os.Environ(), append([]string{"SHELL=/bin/sh"}, env...)...)
	in, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatalf("script(1) cannot start: %v", err)
	}
	return cmd, in
}

// needProgram is the path of a program a terminal test needs. Missing, the test skips, except under the gate
// (ZN_MEASURED, which check.sh sets around its run), where it fails naming the package to install (T8): a gate on a
// machine without it would otherwise pass without the terminal tests.
func needProgram(t *testing.T, name, linuxPackage string) string {
	t.Helper()
	p, err := exec.LookPath(name)
	if err == nil {
		return p
	}
	if os.Getenv("ZN_MEASURED") != "" {
		t.Fatalf("%s is not on PATH, and under the gate a terminal test may not skip: install it (on Linux the %s package)", name, linuxPackage)
	}
	t.Skipf("%s is not on PATH (on Linux the %s package)", name, linuxPackage)
	return ""
}

// endPty ends a terminal test whatever happened: script(1), the helper zn and the engine's group (continued first, so a
// stopped one dies too). A failed test then leaves nothing stopped behind.
func endPty(t *testing.T, dir string, cmd *exec.Cmd, in io.WriteCloser) {
	for _, f := range []string{"zn", "engine"} {
		if pid := pidIn(t, filepath.Join(dir, f)); pid > 1 {
			if pg, err := syscall.Getpgid(pid); err == nil && pg > 1 && pg != syscall.Getpgrp() {
				syscall.Kill(-pg, syscall.SIGCONT)
				syscall.Kill(-pg, syscall.SIGKILL)
			}
			killPid(pid)
		}
	}
	in.Close()
	cmd.Process.Kill()
	cmd.Wait()
}

func psState(pid int) string {
	ps, err := exec.LookPath("ps")
	if err != nil {
		return "(no ps)"
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, _ := exec.CommandContext(ctx, ps, "-o", "stat=", "-p", strconv.Itoa(pid)).Output()
	return strings.TrimSpace(string(out))
}

// Q1: with a terminal, the engine is the terminal's foreground group: a program of the engine that prompts on
// /dev/tty (git asking for a login, ssh for a passphrase) gets the input, and zn has the terminal back afterwards.
func TestAPromptOnTheTerminalWorks(t *testing.T) {
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd, in := underPty(t, ctx, "TestTtyHelper", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=read")
	defer endPty(t, dir, cmd, in)
	if !waitFor(t, filepath.Join(dir, "ready"), 30*time.Second) {
		t.Fatal("the engine never reached its prompt")
	}
	io.WriteString(in, "secret\r")
	if !waitFor(t, filepath.Join(dir, "code"), 20*time.Second) {
		t.Fatalf("zn did not return after the prompt was answered (engine %s)", psState(pidIn(t, filepath.Join(dir, "engine"))))
	}
	if got, _ := os.ReadFile(filepath.Join(dir, "got")); strings.TrimSpace(string(got)) != "secret" {
		t.Errorf("the prompt read %q", got)
	}
	if code, _ := os.ReadFile(filepath.Join(dir, "code")); strings.TrimSpace(string(code)) != "0 fg" {
		t.Errorf("code and terminal: %q, want 0 and the terminal back", code)
	}
}

// Q1: Ctrl-C at the prompt ends the engine (the terminal sends INT to its group once) and zn returns promptly.
func TestCtrlCAtThePromptEndsZn(t *testing.T) {
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd, in := underPty(t, ctx, "TestTtyHelper", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=read")
	defer endPty(t, dir, cmd, in)
	if !waitFor(t, filepath.Join(dir, "ready"), 30*time.Second) {
		t.Fatal("the engine never reached its prompt")
	}
	io.WriteString(in, "\x03")
	if !waitFor(t, filepath.Join(dir, "code"), 10*time.Second) {
		t.Fatalf("zn did not return after Ctrl-C (engine %s)", psState(pidIn(t, filepath.Join(dir, "engine"))))
	}
	if code, _ := os.ReadFile(filepath.Join(dir, "code")); !strings.HasPrefix(string(code), "130 ") {
		t.Errorf("code %q, want 130 (INT)", code)
	}
	if pid := pidIn(t, filepath.Join(dir, "engine")); !gone(pid) {
		killPid(pid)
		t.Error("the engine outlived Ctrl-C")
	}
}

// Q1: with no terminal on zn's standard input (a pipe, CI), a program that reads /dev/tty fails at once instead of
// stopping the engine's group, and nothing is left stopped.
func TestWithNoTerminalAPromptFailsFast(t *testing.T) {
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	cmd, in := underPty(t, ctx, "TestTtyHelper", "ZN_TTY_HELPER="+dir, "ZN_TTY_MODE=notty")
	defer endPty(t, dir, cmd, in)
	if !waitFor(t, filepath.Join(dir, "code"), 20*time.Second) {
		t.Fatalf("zn did not return (engine %s)", psState(pidIn(t, filepath.Join(dir, "engine"))))
	}
	if got, _ := os.ReadFile(filepath.Join(dir, "got")); !strings.HasPrefix(string(got), "rc=") || strings.TrimSpace(string(got)) == "rc=0" {
		t.Errorf("the /dev/tty read: %q, want a failure", got)
	}
}

// TestTtyHelper is the zn the terminal tests run under script(1): it runs only with its variables set.
func TestTtyHelper(t *testing.T) {
	dir := os.Getenv("ZN_TTY_HELPER")
	if dir == "" {
		t.Skip("run by the terminal tests")
	}
	mode := os.Getenv("ZN_TTY_MODE")
	if mode == "nosess" { // run the helper again in a session of its own: the pty is then its stdin, not its terminal
		c := exec.Command(os.Args[0], "-test.run=^TestTtyHelper$")
		c.Env = append(os.Environ(), "ZN_TTY_MODE=where")
		c.Stdin, c.Stdout, c.Stderr = os.Stdin, os.Stdout, os.Stderr
		c.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
		c.Run()
		return
	}
	os.WriteFile(filepath.Join(dir, "zn"), []byte(strconv.Itoa(os.Getpid())+"\n"), 0o644)
	childStdin, stopGroup = os.Stdin, stopOwnGroup // TestMain gave the in-process tests no terminal and a guard
	if mode == "notty" {
		childStdin = strings.NewReader("")
	}
	p := filepath.Join(dir, "engine.sh")
	argv, env := []string{p}, []string{"PATH=/usr/bin:/bin", "ZN_TTY_MODE=" + mode}
	switch mode {
	case "where": // where the terminal is while the engine runs: its foreground group, and the engine's group
		os.WriteFile(p, []byte("#!/bin/sh\necho $$ > "+sq(dir+"/engine")+"\n"+
			"echo $(ps -o tpgid= -p $$) $(ps -o pgid= -p $$) > "+sq(dir+"/where")+"\nexit 0\n"), 0o755)
	case "stop":
		os.WriteFile(p, []byte("#!/bin/sh\necho $$ > "+sq(dir+"/engine")+"\necho ready > "+sq(dir+"/ready")+"\n"+
			"until [ -f "+sq(dir+"/go")+" ]; do /bin/sleep 0.05; done\nexit 0\n"), 0o755)
	case "nostart":
		engineShell = filepath.Join(dir, "no-such-shell")
		os.WriteFile(p, []byte("#!/bin/sh\nexit 0\n"), 0o755)
	case "sigs": // zn started with both ignored. The lifeline's shell is a probe (perl shows an inherited ignore; Go does
		// not, and macOS's sh resets both in every child it forks, but dash need not): what does the runner start with?
		signal.Ignore(syscall.SIGTTIN, syscall.SIGTTOU)
		engineShell = filepath.Join(dir, "sh")
		os.WriteFile(engineShell, []byte("#!/usr/bin/perl\nopen(my $f, '>', '"+dir+"/sigs') or die;\n"+
			"printf $f \"ttin=%s ttou=%s\\n\", map { ($SIG{$_} || '') eq 'IGNORE' ? 'true' : 'false' } qw(TTIN TTOU);\nclose $f;\n"), 0o755)
	default:
		os.WriteFile(p, []byte("#!/bin/sh\necho $$ > '"+dir+"/engine'\necho ready > '"+dir+"/ready'\n"+
			"printf 'Password: ' > /dev/tty 2>/dev/null\nread -r x < /dev/tty\nrc=$?\n"+
			"if [ \"$ZN_TTY_MODE\" = notty ]; then echo \"rc=$rc\" > '"+dir+"/got'; exit 0; fi\necho \"$x\" > '"+dir+"/got'\nexit 0\n"), 0o755)
	}
	code, err := runChild(p, argv, env, io.Discard, io.Discard)
	fg := "bg"
	if pg, e := tcgetpgrp(0); e == nil && pg == syscall.Getpgrp() {
		fg = "fg"
	}
	line := fmt.Sprintf("%d %s", code, fg)
	if err != nil {
		line += " " + err.Error()
	}
	os.WriteFile(filepath.Join(dir, "code.tmp"), []byte(line+"\n"), 0o644)
	os.Rename(filepath.Join(dir, "code.tmp"), filepath.Join(dir, "code"))
}

// Q1, T2: Ctrl-Z (a TSTP to zn) stops the engine and zn's whole group together (the script that started zn sees its job
// stopped), and a CONT to that group continues them all. zn is started by a script, in a group of its own (never the
// test's: zn stops its own group).
func TestStopAndContinueTogether(t *testing.T) {
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	sh := exec.CommandContext(ctx, "/bin/sh", "-c", helperLine("TestStopHelper")+"; echo after > "+sq(dir+"/after"))
	sh.Env = append(os.Environ(), "ZN_STOP_HELPER="+dir)
	sh.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if err := sh.Start(); err != nil {
		t.Fatal(err)
	}
	group := sh.Process.Pid
	defer func() { // the engine's group and zn's, continued first so stopped ones die too
		for _, pg := range []int{pidIn(t, filepath.Join(dir, "engine")), group} {
			if pg > 1 && pg != syscall.Getpgrp() {
				syscall.Kill(-pg, syscall.SIGCONT)
				syscall.Kill(-pg, syscall.SIGKILL)
			}
		}
		sh.Wait()
	}()
	if !waitFor(t, filepath.Join(dir, "ready"), 20*time.Second) {
		t.Fatal("the engine never started")
	}
	zn, engine := pidIn(t, filepath.Join(dir, "zn")), pidIn(t, filepath.Join(dir, "engine"))
	syscall.Kill(zn, syscall.SIGTSTP)
	for _, pid := range []int{zn, engine, group} {
		deadline := time.Now().Add(10 * time.Second)
		for !strings.HasPrefix(psState(pid), "T") && time.Now().Before(deadline) {
			time.Sleep(20 * time.Millisecond)
		}
		if !strings.HasPrefix(psState(pid), "T") {
			t.Fatalf("pid %d is %q after Ctrl-Z, want stopped (zn %d, engine %d, the script %d)", pid, psState(pid), zn, engine, group)
		}
	}
	os.WriteFile(filepath.Join(dir, "go"), nil, 0o644)
	syscall.Kill(-group, syscall.SIGCONT)
	if !waitFor(t, filepath.Join(dir, "done"), 10*time.Second) || !waitFor(t, filepath.Join(dir, "after"), 10*time.Second) {
		t.Errorf("the engine or the script did not go on after CONT (engine %s, zn %s, script %s)", psState(engine), psState(zn), psState(group))
	}
}

// TestStopHelper is the zn TestStopAndContinueTogether stops: it runs only with the variable set.
func TestStopHelper(t *testing.T) {
	dir := os.Getenv("ZN_STOP_HELPER")
	if dir == "" {
		t.Skip("run by TestStopAndContinueTogether")
	}
	os.WriteFile(filepath.Join(dir, "zn"), []byte(strconv.Itoa(os.Getpid())+"\n"), 0o644)
	childStdin, stopGroup = strings.NewReader(""), stopOwnGroup
	p := filepath.Join(dir, "engine.sh")
	os.WriteFile(p, []byte("#!/bin/sh\necho $$ > '"+dir+"/engine'\necho ready > '"+dir+"/ready'\n"+
		"until [ -f '"+dir+"/go' ]; do /bin/sleep 0.05; done\necho done > '"+dir+"/done'\n"), 0o755)
	runChild(p, []string{p}, []string{"PATH=/usr/bin:/bin"}, io.Discard, io.Discard)
}

// Q1: zn's own standard output breaking (zn list | head -1) ends zn's wait with the engine's 141 and nothing left.
func TestZnsOwnBrokenOutput(t *testing.T) {
	dir := resolved(t)
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	helper := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestPipeHelper$")
	helper.Env = append(os.Environ(), "ZN_PIPE_HELPER="+dir)
	out, err := helper.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := helper.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { helper.Process.Kill(); helper.Wait() }()
	b := make([]byte, 5)
	if _, err := io.ReadFull(out, b); err != nil {
		t.Fatalf("no output from the engine: %v", err)
	}
	out.Close() // head -1 leaves
	if !waitFor(t, filepath.Join(dir, "code"), 20*time.Second) {
		t.Fatalf("zn did not return after its output broke (engine %s)", psState(pidIn(t, filepath.Join(dir, "engine"))))
	}
	if code, _ := os.ReadFile(filepath.Join(dir, "code")); strings.TrimSpace(string(code)) != "141" {
		t.Errorf("code %q, want 141", code)
	}
	if pid := pidIn(t, filepath.Join(dir, "engine")); !gone(pid) {
		killPid(pid)
		t.Error("the engine outlived zn's broken output")
	}
}

// TestPipeHelper is the zn TestZnsOwnBrokenOutput reads from: it runs only with the variable set.
func TestPipeHelper(t *testing.T) {
	dir := os.Getenv("ZN_PIPE_HELPER")
	if dir == "" {
		t.Skip("run by TestZnsOwnBrokenOutput")
	}
	childStdin = strings.NewReader("")
	p := filepath.Join(dir, "engine.sh")
	os.WriteFile(p, []byte("#!/bin/sh\necho $$ > '"+dir+"/engine'\nwhile :; do echo line || exit 9; /bin/sleep 0.02; done\n"), 0o755)
	code, _ := runChild(p, []string{p}, []string{"PATH=/usr/bin:/bin"}, newTerminalFilter(os.Stdout), io.Discard)
	os.WriteFile(filepath.Join(dir, "code.tmp"), []byte(strconv.Itoa(code)+"\n"), 0o644)
	os.Rename(filepath.Join(dir, "code.tmp"), filepath.Join(dir, "code"))
}

// Q6: an engine that ended well with a broken output is zn list | head -1: exit 141, not an error.
func TestABrokenOutputWithACleanExitIs141(t *testing.T) {
	dir := resolved(t)
	p := script(t, "echo $$ > '"+dir+"/group'\necho hi\nexit 0\n")
	r := runBounded(t, p, brokenWriter{}, io.Discard, filepath.Join(dir, "group"), 10*time.Second, nil)
	if r.err != nil || r.code != 141 {
		t.Errorf("code %d, err %v, want 141 and no error", r.code, r.err)
	}
}

// Q3: the forms git prints an ssh or file address in are redacted too: host:path (scp form without its user),
// ssh://host/path, and a file address's bare path. A stub ssh prints them; no network is used.
func TestRedactionCoversEveryFormOfTheAddress(t *testing.T) {
	f, hostDir, _, _ := hostWithEngine(t)
	f.step(t, "list")
	stubs := resolved(t)
	os.WriteFile(filepath.Join(stubs, "ssh"), []byte("#!/bin/sh\necho 'fatal: example.invalid:o/tracker.git and ssh://example.invalid/o/tracker.git are gone' >&2\nexit 128\n"), 0o755)
	t.Setenv("PATH", stubs+":"+os.Getenv("PATH"))
	for i, e := range f.d.env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			f.d.env[i] = "PATH=" + stubs + ":" + v
		}
	}
	gitOut(t, filepath.Join(hostDir, ".tracker"), "remote", "set-url", "origin", "git@example.invalid:o/tracker.git")
	f.out.Reset()
	f.errOut.Reset()
	run([]string{"new", "issue", "f", "unreachable", "--desc", "x"}, f.d)
	if all := f.out.String() + f.errOut.String(); strings.Contains(all, "example.invalid") || !strings.Contains(all, "<the tracker's address>") {
		t.Errorf("an ssh form of the address is printed: %q", all)
	}
}

// Q3: a file:// address prints as its bare path in git's words, and that is redacted too.
func TestRedactionCoversAFileAddress(t *testing.T) {
	t.Parallel()
	f, hostDir, bare, _ := hostWithEngine(t)
	f.step(t, "new", "issue", "f", "file-form", "--desc", "x")
	gitOut(t, filepath.Join(hostDir, ".tracker"), "remote", "set-url", "origin", "file://"+bare)
	if err := os.Rename(bare, bare+".away"); err != nil {
		t.Fatal(err)
	}
	f.out.Reset()
	f.errOut.Reset()
	run([]string{"status", "f0001"}, f.d)
	if all := f.out.String() + f.errOut.String(); strings.Contains(all, bare) || strings.Contains(all, filepath.Base(bare)) {
		t.Errorf("the file address's path is printed: %q", all)
	}
}

// Q4: status <id> prepared is refused wherever prepared stands, behind an option with a value too; and the engine
// refuses it itself when a front door started it (its parser is the authority).
func TestStatusPreparedIsRefusedInEveryForm(t *testing.T) {
	t.Parallel()
	f, _, _, eng := hostWithEngine(t)
	f.step(t, "new", "issue", "f", "x", "--desc", "x")
	for _, args := range [][]string{{"status", "f0001", "--x", "y", "prepared"}, {"status", "--project", "up", "f0001", "prepared"}} {
		starts := 0
		child := f.d.child
		f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) { starts++; return 0, nil }
		if code := run(args, f.d); code != exitRefused || starts != 0 {
			t.Errorf("%v: exit %d, %d starts", args, code, starts)
		}
		f.d.child = child
	}
	// the engine itself, started as the front door starts it
	luns, _ := filepath.Glob(filepath.Join(eng.cacheDir, "zn", "*", "bin", "lune"))
	if len(luns) != 1 {
		t.Fatalf("no extracted payload: %v", luns)
	}
	payloadDir := filepath.Dir(filepath.Dir(luns[0]))
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, luns[0], "run", filepath.Join(payloadDir, "z-nile", "engine", "main"), "--", "status", "f0001", "prepared")
	cmd.Dir, cmd.Env = eng.dir, eng.env
	out, err := cmd.CombinedOutput()
	if err == nil || !strings.Contains(string(out), "prepared") || !strings.Contains(string(out), "host") {
		t.Errorf("the engine let status prepared through in a host: %v\n%s", err, out)
	}
}

// Q7: an engine that never started is reported as a noexec mount, exits 4 and refreshes nothing; an engine that ran and
// ended with an error exits 1 even when its status was 0.
func TestAnEngineThatNeverStartedIsNotRefreshed(t *testing.T) {
	t.Parallel()
	f, _, bare, _ := hostWithEngine(t)
	f.step(t, "list")
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) {
		pushToTracker(t, bare, map[string]*string{"later.txt": text("x")}, nil)
		return 0, fmt.Errorf("%w: exec format error", errNotStarted)
	}
	f.errOut.Reset()
	if code := run([]string{"list"}, f.d); code != exitRefused {
		t.Errorf("exit %d, want %d", code, exitRefused)
	}
	if !strings.Contains(f.errOut.String(), "noexec") || strings.Contains(f.errOut.String(), "moved the standing worktree") {
		t.Errorf("stderr %q", f.errOut.String())
	}
}

// Q8: a tag named main on the tracker's remote never starves the engine's fetch of main: a publish that meets a main
// pushed after zn prepared still sees it and publishes.
func TestATagNamedMainDoesNotStarveThePublish(t *testing.T) {
	t.Parallel()
	f, _, bare, _ := hostWithEngine(t)
	f.step(t, "list")
	other := filepath.Join(resolved(t), "tagger")
	gitOut(t, filepath.Dir(other), "clone", "-q", bare, other)
	gitOut(t, other, "tag", "main")
	gitOut(t, other, "push", "-q", "origin", "refs/tags/main")
	engine := f.d.child
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) {
		pushToTracker(t, bare, map[string]*string{"meanwhile.txt": text("x")}, nil) // after zn prepared
		return engine(path, argv, env, out, errw)
	}
	f.errOut.Reset()
	if code := run([]string{"new", "issue", "f", "contended", "--desc", "x"}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	files := gitOut(t, bare, "ls-tree", "-r", "--name-only", "refs/heads/main")
	if !strings.Contains(files, "meanwhile.txt") || !strings.Contains(files, "up/.tracker/issues/f0001/f0001.md") {
		t.Errorf("main lacks the other push or the new ticket:\n%s", files)
	}
}
