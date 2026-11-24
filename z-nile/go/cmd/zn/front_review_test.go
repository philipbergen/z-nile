package main

import (
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"znile/internal/host"
)

// builtInAHost is every engine command the front door lets through: the ones proven in a host.
var builtInAHost = map[string]bool{"new": true, "list": true, "audit": true, "status": true, "guesses": true, "find": true}

// engineCommands are the command names the engine's own usage text lists, so a command added to the engine is in the
// table of the next test without anyone remembering it.
func engineCommands(t *testing.T) []string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(engineRoot(t), "z-nile", "engine", "main.luau"))
	if err != nil {
		t.Fatal(err)
	}
	text := string(b)
	at := strings.Index(text, "usage: ./zn <command>")
	if at < 0 {
		t.Fatal("no usage text in the engine")
	}
	end := at + 20000
	if end > len(text) {
		end = len(text)
	}
	seen := map[string]bool{}
	for _, m := range regexp.MustCompile(`(?m)^  ([a-z][a-z-]*)[ \[<]`).FindAllStringSubmatch(text[at:end], -1) {
		seen[m[1]] = true
	}
	var names []string
	for n := range seen {
		names = append(names, n)
	}
	sort.Strings(names)
	if len(names) < 30 {
		t.Fatalf("read only %d commands from the engine's usage: %v", len(names), names)
	}
	return names
}

// hostWithEngine is a host after `zn init`, standing in a subfolder, with the real engine ready to run.
func hostWithEngine(t *testing.T) (f *fake, hostDir, bare string, eng *engineRun) {
	t.Helper()
	f, hostDir, bare = initHost(t)
	if code := run([]string{"init", bare}, f.d); code != 0 {
		t.Fatalf("init: exit %d: %s", code, f.errOut.String())
	}
	os.MkdirAll(filepath.Join(hostDir, "src"), 0o755)
	f.d.cwd = func() (string, error) { return filepath.Join(hostDir, "src"), nil }
	f.out.Reset()
	return f, hostDir, bare, realEngine(t, f)
}

func (f *fake) step(t *testing.T, args ...string) string {
	t.Helper()
	f.out.Reset()
	f.errOut.Reset()
	if code := run(args, f.d); code != 0 {
		t.Fatalf("zn %v: exit %d: %s%s", args, code, f.out.String(), f.errOut.String())
	}
	return f.out.String()
}

// A: only what is built runs in a host. Every other command of the engine, one the engine will gain and `new raft`
// are refused before the engine starts, naming the command, and nothing is written.
func TestOnlyWhatIsBuiltRunsInAHost(t *testing.T) {
	f, hostDir, _, _ := hostWithEngine(t)
	starts := 0
	f.d.exec = func(path string, argv, env []string) error { starts++; return nil }
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) { starts++; return 0, nil }
	tr := filepath.Join(hostDir, ".tracker")
	before := gitOut(t, tr, "for-each-ref")
	var refused [][]string
	for _, n := range engineCommands(t) {
		if !builtInAHost[n] {
			refused = append(refused, []string{n})
		}
	}
	refused = append(refused, []string{"a-command-the-engine-will-gain"}, []string{"new", "raft", "feature", "x", "f0001"}, []string{"new"})
	for _, args := range refused {
		f.errOut.Reset()
		if code := run(args, f.d); code != exitRefused {
			t.Errorf("%v: exit %d, want %d", args, code, exitRefused)
		}
		if !strings.Contains(f.errOut.String(), args[0]) || !strings.Contains(f.errOut.String(), "not yet available in a host repository") ||
			!strings.Contains(f.errOut.String(), "new issue, list, audit, status, guesses and find") {
			t.Errorf("%v: stderr %q", args, f.errOut.String())
		}
	}
	if starts != 0 {
		t.Errorf("the engine started %d times for refused commands", starts)
	}
	if _, err := os.Lstat(filepath.Join(tr, ".worktree")); err == nil {
		t.Error("a refused command made the worktree")
	}
	if gitOut(t, tr, "for-each-ref") != before {
		t.Error("the tracker's refs changed")
	}
	for _, args := range [][]string{{"new", "issue", "f", "x"}, {"list"}, {"audit"}, {"status"}, {"guesses", "f0001"}, {"find", "f0001"}, {"--help"}, {"help"}, {"version"}} {
		starts = 0
		if code := run(args, f.d); code != 0 || (args[0] != "version" && starts != 1) {
			t.Errorf("%v: exit %d, %d starts: %s", args, code, starts, f.errOut.String())
		}
	}
}

// D: git's location and config variables never reach the engine: a hook run with GIT_DIR set to the host cannot make
// zn commit or push on the host.
func TestGitLocationVariablesNeverReachTheEngine(t *testing.T) {
	f, hostDir, bare, eng := hostWithEngine(t)
	f.d.env = append(f.d.env, "GIT_DIR="+filepath.Join(hostDir, ".git"), "GIT_WORK_TREE="+hostDir, "GIT_INDEX_FILE="+filepath.Join(hostDir, ".git", "index"),
		"GIT_COMMON_DIR="+filepath.Join(hostDir, ".git"), "GIT_NAMESPACE=x", "GIT_CONFIG_COUNT=1", "GIT_CONFIG_KEY_0=core.hooksPath", "GIT_CONFIG_VALUE_0=/x",
		"GIT_OBJECT_DIRECTORY="+filepath.Join(hostDir, ".git", "objects"), "GIT_ALTERNATE_OBJECT_DIRECTORIES=/x", "LD_PRELOAD=/x", "DYLD_INSERT_LIBRARIES=/x",
		// zn's own switches that would send the engine's git, gh or publishing elsewhere, or run another program
		"ZN_REAL_GIT=/x", "PICKMAN_FENCE_REAL_GIT=/x", "ZN_REAL_GH=/x", "ZN_PUBLISH_BROKER=/x", "PICKMAN_FENCE_HOOKS=/x", "ZN_ROOT=/x",
		"ZN_LIVE_BIN=/x", "ZN_MEASURE_FILE=/x", "ZN_DISPATCH_DIR=/x", "PICKMAN_TEST_FENCE=/x", "ZN_TOP=/x", "ZN_CWD=x",
		// N10(a): names nobody listed, so a denylist would let them through
		"BASH_ENV=/x", "FOO=/x", "ENV=/x")
	hostSnap, _ := openHost(t, hostDir).Snapshot()
	hostRefs := gitOut(t, hostDir, "for-each-ref")
	hostHead := gitOut(t, hostDir, "symbolic-ref", "HEAD")
	f.step(t, "new", "issue", "f", "from-a-hook", "--desc", "x")
	after, _ := openHost(t, hostDir).Snapshot()
	if d := host.Diff(hostSnap, after); len(d) != 0 {
		t.Errorf("the host changed: %v", d)
	}
	if gitOut(t, hostDir, "for-each-ref") != hostRefs || gitOut(t, hostDir, "symbolic-ref", "HEAD") != hostHead || gitOut(t, hostDir, "status", "--porcelain") != "" {
		t.Error("the host's history or tree changed")
	}
	if gitOut(t, bare, "rev-list", "--count", "main") != "2" || !strings.Contains(gitOut(t, bare, "show", "main:up/.tracker/issues/f0001/f0001.md"), "rom a hook") {
		t.Error("the tracker's main lacks the new ticket")
	}
	kept := map[string]bool{"PATH": true, "HOME": true, "ZN_CACHE": true, "ZN_ENGINE_CPU": true, "ZN_TOP": true, "ZN_CWD": true, "ZN_LIVE": true, "ZN_ABSOLUTE_PATHS": true}
	for _, e := range eng.env {
		k, v, _ := strings.Cut(e, "=")
		switch {
		case v == "/x" || k == "ZN_CWD" && v == "x" || v == "core.hooksPath" && k == "GIT_CONFIG_KEY_0" && strings.Contains(strings.Join(eng.env, "\n"), "GIT_CONFIG_VALUE_0=/x"):
			t.Errorf("the engine got the caller's %s", k)
		case k == "GIT_CONFIG_COUNT" || strings.HasPrefix(k, "GIT_CONFIG_KEY_") || strings.HasPrefix(k, "GIT_CONFIG_VALUE_"):
			// zn's own pins (N2(b)), checked by value above: the caller's GIT_CONFIG_VALUE_0=/x never among them
		case strings.HasPrefix(k, "GIT_") && k != "GIT_TERMINAL_PROMPT" || k == "LD_PRELOAD" || k == "DYLD_INSERT_LIBRARIES":
			t.Errorf("the engine inherited %s", k)
		case (strings.HasPrefix(k, "ZN_") || strings.HasPrefix(k, "PICKMAN_")) && !kept[k]:
			t.Errorf("the engine inherited %s", k)
		}
	}
	joined := strings.Join(eng.env, "\n") + "\n"
	for _, want := range []string{"ZN_LIVE=off\n", "ZN_ABSOLUTE_PATHS=1\n", "HOME=", "PATH="} {
		if !strings.Contains(joined, want) {
			t.Errorf("the engine's environment lacks %s", want)
		}
	}
}

// E: the paths the engine prints are absolute inside the tracker worktree, so `$(zn find <id>)/x` is right from the
// host's top and from a subfolder, and never a path inside the host.
func TestPrintedPathsAreAbsoluteInTheTracker(t *testing.T) {
	f, hostDir, _, _ := hostWithEngine(t)
	out := f.step(t, "new", "issue", "f", "paths", "--desc", "x")
	id := regexp.MustCompile(`(f\d{4})`).FindString(out)
	work := filepath.Join(hostDir, ".tracker", ".worktree", "zn")
	if want := filepath.Join(work, "up", ".tracker", "issues", id, id+".md"); strings.TrimSpace(out) != want {
		t.Errorf("new printed %q, want %q", out, want)
	}
	for _, from := range []string{hostDir, filepath.Join(hostDir, "src")} {
		f.d.cwd = func() (string, error) { return from, nil }
		got := strings.TrimSpace(f.step(t, "find", id))
		if want := filepath.Join(work, "up", ".tracker", "issues", id); got != want {
			t.Errorf("from %s: find printed %q, want %q", from, got, want)
		}
		if _, err := os.Stat(filepath.Join(got, id+".md")); err != nil {
			t.Errorf("from %s: the printed path does not hold the ticket: %v", from, err)
		}
	}
}

// G: the tracker's lock is held for the whole engine run.
func TestTheLockIsHeldWhileTheEngineRuns(t *testing.T) {
	f, hostDir, _, _ := hostWithEngine(t)
	held := false
	f.d.exec = func(path string, argv, env []string) error {
		_, err := host.LockTracker(filepath.Join(hostDir, ".tracker"), 200*time.Millisecond)
		held = err != nil && strings.Contains(err.Error(), "pid")
		return nil
	}
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) {
		return 0, f.d.exec(path, argv, env)
	}
	if code := run([]string{"list"}, f.d); code != 0 || !held {
		t.Errorf("exit %d, lock held during the engine: %v", code, held)
	}
	l, err := host.LockTracker(filepath.Join(hostDir, ".tracker"), time.Second)
	if err != nil {
		t.Errorf("the lock was not given back: %v", err)
	} else {
		l.Release()
	}
}

// J: with several projects, the folder the caller is in picks the project; elsewhere none is picked.
func TestSeveralProjectsFollowTheFolder(t *testing.T) {
	f, hostDir, bare, eng := hostWithEngine(t)
	f.step(t, "list") // makes the standing worktree
	other := filepath.Join(resolved(t), "other")
	gitOut(t, filepath.Dir(other), "clone", "-q", bare, other)
	reg := filepath.Join(other, "z-nile", "projects.toml")
	b, _ := os.ReadFile(reg)
	os.WriteFile(reg, append(b, []byte("\n[[project]]\nname = \"two\"\nroot = \"two/.tracker\"\n")...), 0o644)
	os.MkdirAll(filepath.Join(other, "two", ".tracker", "issues"), 0o755)
	os.WriteFile(filepath.Join(other, "two", ".tracker", "issues", ".gitkeep"), nil, 0o644)
	gitOut(t, other, "add", "-A")
	gitOut(t, other, "commit", "-q", "-m", "two")
	gitOut(t, other, "push", "-q", "origin", "main")
	zncwd := func() string {
		for _, e := range eng.env {
			if v, ok := strings.CutPrefix(e, "ZN_CWD="); ok {
				return v
			}
		}
		return "unset"
	}
	f.step(t, "list")
	if got := zncwd(); got != "" && got != "unset" {
		t.Errorf("from the host's src with two projects: ZN_CWD %q", got)
	}
	work := filepath.Join(hostDir, ".tracker", ".worktree", "zn")
	f.d.cwd = func() (string, error) { return filepath.Join(work, "two"), nil }
	f.step(t, "list")
	if got := zncwd(); got != "two" {
		t.Errorf("from the tracker worktree's two/: ZN_CWD %q, want two", got)
	}
}

// E: audit names each problem by its absolute path in the tracker worktree, so it can be opened from the host.
func TestAuditPrintsAbsolutePaths(t *testing.T) {
	f, hostDir, bare, eng := hostWithEngine(t)
	other := filepath.Join(resolved(t), "other")
	gitOut(t, filepath.Dir(other), "clone", "-q", bare, other)
	os.MkdirAll(filepath.Join(other, "up", ".tracker", "issues", "f0009"), 0o755)
	os.WriteFile(filepath.Join(other, "up", ".tracker", "issues", "f0009", "f0009.md"), []byte("no front matter\n"), 0o644)
	gitOut(t, other, "add", "-A")
	gitOut(t, other, "commit", "-q", "-m", "a broken ticket")
	gitOut(t, other, "push", "-q", "origin", "main")
	f.out.Reset()
	if code := run([]string{"audit"}, f.d); code != 0 || eng.code == 0 {
		t.Fatalf("audit: exit %d, engine %d: %s%s", code, eng.code, f.out.String(), f.errOut.String())
	}
	work := filepath.Join(hostDir, ".tracker", ".worktree", "zn")
	named := false
	for _, line := range strings.Split(strings.TrimSpace(f.out.String()), "\n") {
		if strings.HasPrefix(line, "audit:") {
			continue
		}
		// <level> <code> <path>: <message>
		if fields := strings.Fields(line); len(fields) < 3 || !strings.HasPrefix(fields[2], work+"/") {
			t.Errorf("a problem not named by its absolute path in %s: %q", work, line)
		}
		named = named || strings.Contains(line, " "+filepath.Join(work, "up", ".tracker", "issues", "f0009"))
	}
	if !named {
		t.Errorf("audit did not name the broken ticket: %q", f.out.String())
	}
}

// L: the registry read the front door starts is bounded, and stops everything it started.
func TestTheRegistryReadIsBounded(t *testing.T) {
	dir := resolved(t)
	pidFile := filepath.Join(dir, "child")
	fake := filepath.Join(dir, "bin", "lune")
	os.MkdirAll(filepath.Dir(fake), 0o755)
	os.WriteFile(fake, []byte("#!/bin/sh\nsleep 30 &\necho $! > '"+pidFile+"'\nwait\n"), 0o755)
	projectsTimeout = 500 * time.Millisecond
	defer func() { projectsTimeout = time.Minute }()
	start := time.Now()
	if _, err := projectHomes(dir, dir, []string{"PATH=/usr/bin:/bin"}); err == nil {
		t.Error("a registry read that never ended succeeded")
	}
	if d := time.Since(start); d > 5*time.Second {
		t.Errorf("the read took %s", d)
	}
	b, _ := os.ReadFile(pidFile)
	pid, _ := strconv.Atoi(strings.TrimSpace(string(b)))
	for i := 0; i < 50 && pid > 0 && syscall.Kill(pid, 0) == nil; i++ {
		time.Sleep(20 * time.Millisecond)
	}
	if pid <= 0 || syscall.Kill(pid, 0) == nil {
		if pid > 0 {
			syscall.Kill(pid, syscall.SIGKILL)
		}
		t.Errorf("the read's child (pid %d) outlived it", pid)
	}
}

// E: the registry is read with the payload's own reader, named by its absolute path, never a file of the tracker's.
func TestTheRegistryIsReadByThePayloadsReader(t *testing.T) {
	dir := resolved(t)
	payloadDir, work := filepath.Join(dir, "payload"), filepath.Join(dir, "work")
	os.MkdirAll(filepath.Join(payloadDir, "bin"), 0o755)
	os.MkdirAll(filepath.Join(work, "z-nile"), 0o755)
	argsFile := filepath.Join(dir, "args")
	os.WriteFile(filepath.Join(payloadDir, "bin", "lune"), []byte("#!/bin/sh\necho \"$@\" > '"+argsFile+"'\nprintf 'up\\tup\\tup/.tracker\\n'\n"), 0o755)
	homes, err := projectHomes(payloadDir, work, []string{"PATH=/usr/bin:/bin"})
	if err != nil || len(homes) != 1 || homes[0] != "up" {
		t.Fatalf("%v %v", homes, err)
	}
	if got, want := strings.TrimSpace(readFile(t, argsFile)), "run "+filepath.Join(payloadDir, "z-nile", "roots")+" -- --projects"; got != want {
		t.Errorf("the reader was started as %q, want %q", got, want)
	}
}

func readFile(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}
