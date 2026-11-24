package main

import (
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"znile/internal/host"
)

// The third review round of f0428 step 4: each test names the finding it guards.

// pushToTracker commits files (a nil body removes the path) and links in a fresh clone of the bare tracker, as another
// machine would, and pushes it to main.
func pushToTracker(t *testing.T, bare string, files map[string]*string, links map[string]string) {
	t.Helper()
	other := filepath.Join(resolved(t), "other")
	gitOut(t, filepath.Dir(other), "clone", "-q", bare, other)
	for p, body := range files {
		if body == nil {
			gitOut(t, other, "rm", "-q", "-r", "-f", p)
			continue
		}
		os.MkdirAll(filepath.Dir(filepath.Join(other, p)), 0o755)
		os.WriteFile(filepath.Join(other, p), []byte(*body), 0o755)
	}
	for p, target := range links {
		os.MkdirAll(filepath.Dir(filepath.Join(other, p)), 0o755)
		os.Symlink(target, filepath.Join(other, p))
	}
	gitOut(t, other, "add", "-A", "-f")
	gitOut(t, other, "commit", "-q", "-m", "from another machine")
	gitOut(t, other, "push", "-q", "origin", "main")
}

func text(s string) *string { return &s }

// homeOfEnv is the HOME the engine is given.
func homeOfEnv(env []string) string {
	for _, e := range env {
		if v, ok := strings.CutPrefix(e, "HOME="); ok {
			return v
		}
	}
	return ""
}

// N1: a commit pushed while the engine runs (after the front door judged the tracker) is never checked out: not by the
// engine's merge after it publishes, and not by the front door's refresh after the engine, which refuses it. Nothing is
// written outside .tracker.
func TestACommitPushedDuringTheRunIsNeverCheckedOut(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name  string
		files map[string]*string
		links map[string]string
		bad   string
	}{
		{"a .cache link and code", map[string]*string{".claude/settings.json": text("{}")}, map[string]string{".cache": "../../.."}, ".claude/settings.json"},
		{"a folder where the lib link goes", map[string]*string{"z-nile/lib/fence.sh": text("touch pwned\n")}, nil, "z-nile/lib/fence.sh"},
	} {
		t.Run(c.name, func(t *testing.T) {
			f, hostDir, bare, _ := hostWithEngine(t)
			f.step(t, "list") // the standing worktree, judged
			work := filepath.Join(hostDir, ".tracker", ".worktree", "zn")
			hostSnap, _ := openHost(t, hostDir).Snapshot()
			hostFiles := gitOut(t, hostDir, "status", "--porcelain", "--ignored", "--untracked-files=all")
			engine := f.d.child
			pushed := false
			f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) {
				pushToTracker(t, bare, c.files, c.links) // just before the engine starts
				pushed = true
				return engine(path, argv, env, out, errw)
			}
			f.out.Reset()
			f.errOut.Reset()
			run([]string{"new", "issue", "f", "raced", "--desc", "x"}, f.d)
			if !pushed {
				t.Fatal("the engine never started")
			}
			if st, err := os.Lstat(filepath.Join(work, ".cache")); err == nil && st.Mode()&os.ModeSymlink != 0 {
				t.Error("the pushed .cache link was checked out")
			}
			if _, err := os.Lstat(filepath.Join(work, c.bad)); err == nil {
				if st, _ := os.Lstat(filepath.Join(work, filepath.Dir(c.bad))); st == nil || st.Mode()&os.ModeSymlink == 0 {
					t.Errorf("%s was checked out", c.bad)
				}
			}
			if files := gitOut(t, work, "ls-tree", "-r", "--name-only", "HEAD"); strings.Contains(files, c.bad) {
				t.Errorf("the worktree's HEAD holds %s", c.bad)
			}
			after, _ := openHost(t, hostDir).Snapshot()
			if d := host.Diff(hostSnap, after); len(d) != 0 {
				t.Errorf("the host's git directory changed: %v", d)
			}
			if got := gitOut(t, hostDir, "status", "--porcelain", "--ignored", "--untracked-files=all"); got != hostFiles {
				t.Errorf("files appeared in the host:\n%s\nwas\n%s", got, hostFiles)
			}
			if !strings.Contains(f.errOut.String(), "a tracker is data") {
				t.Errorf("the refresh after the run did not refuse the pushed commit: %q", f.errOut.String())
			}
		})
	}
}

// N1: the worktree catches up with what the engine published, through the front door's check, so the path `new`
// prints holds the ticket when the command returns.
func TestTheWorktreeCatchesUpAfterTheRun(t *testing.T) {
	t.Parallel()
	f, _, _, _ := hostWithEngine(t)
	got := strings.TrimSpace(f.step(t, "new", "issue", "f", "caught-up", "--desc", "x"))
	if _, err := os.Stat(got); err != nil {
		t.Errorf("the printed path does not hold the ticket: %v", err)
	}
}

// N2(a): a relative PATH entry never reaches the engine, so a program the tracker holds (bin/git) never runs after zn
// changes into the tracker's worktree.
func TestARelativePathEntryRunsNothing(t *testing.T) {
	t.Parallel()
	f, _, bare, eng := hostWithEngine(t)
	marker := filepath.Join(resolved(t), "ran")
	pushToTracker(t, bare, map[string]*string{"bin/git": text("#!/bin/sh\n: > '" + marker + "'\nexec /usr/bin/git \"$@\"\n")}, nil)
	for i, e := range f.d.env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			f.d.env[i] = "PATH=./bin:bin::" + v
		}
	}
	f.step(t, "list")
	f.step(t, "new", "issue", "f", "relative-path", "--desc", "x")
	if _, err := os.Stat(marker); err == nil {
		t.Error("the tracker's bin/git ran")
	}
	for _, e := range eng.env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			for _, part := range strings.Split(v, ":") {
				if !filepath.IsAbs(part) {
					t.Errorf("a relative PATH entry %q reached the engine", part)
				}
			}
		}
	}
}

// N2(b): the engine's git runs with zn's pins, so a relative hooksPath in the owner's global config never runs a hook
// the tracker holds.
func TestARelativeGlobalHooksPathRunsNoTrackedHook(t *testing.T) {
	f, _, bare, eng := hostWithEngine(t)
	marker := filepath.Join(resolved(t), "hooked")
	hook := text("#!/bin/sh\n: > '" + marker + "'\n")
	pushToTracker(t, bare, map[string]*string{".githooks/pre-push": hook, ".githooks/reference-transaction": hook,
		".githooks/post-checkout": hook, ".githooks/pre-commit": hook, ".githooks/post-merge": hook}, nil)
	home := homeOfEnv(f.d.env)
	cfg, _ := os.ReadFile(filepath.Join(home, ".gitconfig"))
	os.WriteFile(filepath.Join(home, ".gitconfig"), append(cfg, []byte("[core]\n\thooksPath = .githooks\n")...), 0o644)
	f.step(t, "list")
	f.step(t, "new", "issue", "f", "hooked", "--desc", "x")
	if _, err := os.Stat(marker); err == nil {
		t.Error("a hook the tracker holds ran")
	}
	pins := map[string]string{}
	for _, e := range eng.env {
		k, v, _ := strings.Cut(e, "=")
		pins[k] = v
	}
	if pins["GIT_CONFIG_COUNT"] == "" {
		t.Fatalf("no config pins for the engine: %v", eng.env)
	}
	want := map[string]bool{"core.hooksPath": true, "core.fsmonitor": true, "gc.auto": true, "maintenance.auto": true,
		"protocol.ext.allow": true, "protocol.fd.allow": true, "submodule.recurse": true}
	for i := 0; i < 20; i++ {
		if k, ok := pins["GIT_CONFIG_KEY_"+strconv.Itoa(i)]; ok {
			delete(want, k)
		}
	}
	if len(want) != 0 {
		t.Errorf("pins missing: %v", want)
	}
}

// N5: the lock is zn's alone: a program the engine leaves running does not hold it once zn has returned.
func TestTheEnginesChildrenDoNotHoldTheLock(t *testing.T) {
	t.Parallel()
	f, hostDir, _, _ := hostWithEngine(t)
	f.step(t, "list")
	linger := func() {
		cmd := exec.Command("/bin/sh", "-c", "/bin/sleep 4 >/dev/null 2>&1 &")
		cmd.Run()
	}
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) { linger(); return 0, nil }
	f.d.exec = func(path string, argv, env []string) error { linger(); return nil }
	if code := run([]string{"list"}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	l, err := host.LockTracker(filepath.Join(hostDir, ".tracker"), 300*time.Millisecond)
	if err != nil {
		t.Errorf("a program the engine left running holds the lock: %v", err)
	} else {
		l.Release()
	}
}

// N4(d): the way out a refusal gives works through zn itself: after the bad push is removed upstream, the next command
// runs.
func TestTheWayOutWorksThroughZn(t *testing.T) {
	t.Parallel()
	f, _, bare, _ := hostWithEngine(t)
	f.step(t, "list")
	pushToTracker(t, bare, map[string]*string{"AGENTS.md": text("x")}, nil)
	f.errOut.Reset()
	if code := run([]string{"list"}, f.d); code != exitRefused || !strings.Contains(f.errOut.String(), "AGENTS.md") {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	pushToTracker(t, bare, map[string]*string{"AGENTS.md": nil}, nil)
	f.step(t, "list")
}

// E: list's problem lines name each problem by its absolute path in the tracker worktree.
func TestListPrintsAbsolutePaths(t *testing.T) {
	t.Parallel()
	f, hostDir, bare, _ := hostWithEngine(t)
	pushToTracker(t, bare, map[string]*string{"up/.tracker/issues/f0009/f0009.md": text("no front matter\n")}, nil)
	f.errOut.Reset()
	run([]string{"list"}, f.d)
	work := filepath.Join(hostDir, ".tracker", ".worktree", "zn")
	named := false
	for _, line := range strings.Split(strings.TrimSpace(f.errOut.String()), "\n") {
		if fields := strings.Fields(line); len(fields) >= 3 && (fields[0] == "error" || fields[0] == "warning") {
			named = true
			if !strings.HasPrefix(fields[2], work+"/") {
				t.Errorf("a problem not named by its absolute path in %s: %q", work, line)
			}
		}
	}
	if !named {
		t.Errorf("list named no problem: %q", f.errOut.String())
	}
}

// N4(c): what the engine prints from the tracker reaches the terminal with its control bytes escaped, so a title cannot
// move the cursor, clear the screen or change the window title.
func TestTrackerTextIsEscapedForTheTerminal(t *testing.T) {
	t.Parallel()
	f, _, bare, _ := hostWithEngine(t)
	f.step(t, "new", "issue", "f", "plain", "--desc", "x")
	other := filepath.Join(resolved(t), "edit")
	gitOut(t, filepath.Dir(other), "clone", "-q", bare, other)
	doc := filepath.Join(other, "up", ".tracker", "issues", "f0001", "f0001.md")
	b, _ := os.ReadFile(doc)
	os.WriteFile(doc, []byte(strings.Replace(string(b), "title: Plain", "title: Plain \x1b]0;owned\x07\x1b[2J\u009b31m", 1)), 0o644)
	gitOut(t, other, "commit", "-q", "-am", "a title with control bytes")
	gitOut(t, other, "push", "-q", "origin", "main")
	out := f.step(t, "list")
	if strings.ContainsAny(out, "\x1b\x07\u009b") {
		t.Errorf("raw control bytes reached the terminal: %q", out)
	}
	if !strings.Contains(out, `\x1b`) {
		t.Errorf("the title is not shown escaped: %q", out)
	}
}

// N10(b): under the gate a real-engine test that finds no pinned Lune fails instead of skipping.
func TestAMissingLuneFailsUnderTheGate(t *testing.T) {
	t.Parallel()
	if !luneMissingIsFatal(func(k string) string { return map[string]string{"ZN_MEASURED": "1"}[k] }) {
		t.Error("under the gate a missing Lune is skipped")
	}
	if luneMissingIsFatal(func(string) string { return "" }) {
		t.Error("outside the gate a missing Lune fails")
	}
}

// N10(c): the tests' own git ignores the caller's git variables.
func TestGitOutIgnoresTheCallersGitVariables(t *testing.T) {
	dir := resolved(t)
	gitOut(t, dir, "init", "-q", "-b", "main")
	t.Setenv("GIT_DIR", filepath.Join(resolved(t), "decoy"))
	t.Setenv("GIT_WORK_TREE", resolved(t))
	if got := gitOut(t, dir, "rev-parse", "--show-toplevel"); got != dir {
		t.Errorf("gitOut followed GIT_DIR: %q", got)
	}
}
