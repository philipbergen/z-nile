package main

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"

	"znile/internal/host"
	"znile/internal/lunepin"
	"znile/internal/payload"
)

// startPath and startHome are the PATH and HOME the test process started with: newFake replaces PATH with a decoy folder
// and a test replaces HOME, so a real Lune is looked for with these.
var (
	startPath = os.Getenv("PATH")
	startHome = os.Getenv("HOME")
)

// findLune is the Lune the build pins and verifies (cmd/zn/lune.sum), or none (lunepin.Find: a rokit shim is never run,
// and a candidate counts only by the pinned digest, or under a zip pin by the pinned version with an empty PATH).
func findLune() (string, bool) {
	sum, err := os.ReadFile("lune.sum")
	if err != nil {
		return "", false
	}
	return lunepin.Find(string(sum), startPath, startHome)
}

// engineRoot is the checkout this module is in, which holds the engine the real-engine tests pack.
func engineRoot(t *testing.T) string {
	t.Helper()
	d, _ := filepath.Abs(".")
	for ; d != filepath.Dir(d); d = filepath.Dir(d) {
		if _, err := os.Stat(filepath.Join(d, "z-nile", "engine", "main.luau")); err == nil {
			return d
		}
	}
	t.Skip("no engine beside the module")
	return ""
}

// realEngine puts the real Lune and this checkout's engine into the fake's payload and lets its exec run the engine as
// a child (a real exec would replace the test): it records the folder the engine ran in, its environment and its exit
// code, and prints its output into the fake's stdout.
type engineRun struct {
	dir  string
	env  []string
	code int
	cwd  string // what zn changed to
}

func realEngine(t *testing.T, f *fake) *engineRun {
	t.Helper()
	lune, ok := findLune()
	if !ok {
		if luneMissingIsFatal(os.Getenv) {
			t.Fatal("no Lune that matches cmd/zn/lune.sum was found, and under the gate a real-engine test may not skip")
		}
		t.Skip("no Lune that matches cmd/zn/lune.sum was found: the test will not run an unverified binary")
	}
	root := engineRoot(t)
	luneBytes, err := os.ReadFile(lune)
	if err != nil {
		t.Fatal(err)
	}
	var tarBuf bytes.Buffer
	if _, err := payload.Pack(root, []string{"z-nile/engine", "z-nile/lib", "z-nile/vendor", "z-nile/templates", "z-nile/roots.luau", "z-nile/affected.luau"}, &tarBuf); err != nil {
		t.Fatal(err)
	}
	p := payload.New(luneBytes, tarBuf.Bytes(), "kind bin\n")
	f.d.embedded = func() (payload.Payload, bool) { return p, true }
	cache := filepath.Join(resolved(t), "cache")
	f.d.env = append(f.d.env, "ZN_CACHE="+cache, "ZN_ENGINE_CPU=600")
	r := &engineRun{}
	f.d.chdir = func(dir string) error { r.cwd = dir; return nil }
	start := func(path string, argv, env []string, out, errw io.Writer) int {
		// bounded: a runaway engine is killed with everything it started, after two minutes
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
		defer cancel()
		if b, err := os.ReadFile(path); err != nil || !bytes.Equal(b, luneBytes) || filepath.Base(path) != "lune" || !strings.HasPrefix(path, cache+"/") {
			t.Fatalf("zn started %s, not the payload's own Lune extracted to %s", path, cache)
		}
		cmd := lunepin.Command(ctx, path, argv[1:]...)
		cmd.Dir = r.cwd
		if cmd.Dir == "" {
			cmd.Dir, _ = f.d.cwd()
		}
		cmd.Env = env
		cmd.Stdout, cmd.Stderr = out, errw
		r.dir, r.env = cmd.Dir, env
		err := cmd.Run()
		var ee *exec.ExitError
		switch {
		case err == nil:
			r.code = 0
		case errors.As(err, &ee):
			r.code = ee.ExitCode()
		default:
			t.Fatal(err)
		}
		return r.code
	}
	f.d.exec = func(path string, argv, env []string) error { start(path, argv, env, &f.out, &f.errOut); return nil }
	f.d.child = func(path string, argv, env []string, out, errw io.Writer) (int, error) {
		return start(path, argv, env, out, errw), nil
	}
	return r
}

// luneMissingIsFatal says a real-engine test that finds no pinned Lune fails rather than skips: under the gate
// (check.sh runs inside one measured run, ZN_MEASURED), where a skip would pass the gate without the test.
func luneMissingIsFatal(getenv func(string) string) bool { return getenv("ZN_MEASURED") != "" }

func gitOut(t *testing.T, dir string, args ...string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute) // bounded, like every process a test starts
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
	var env []string
	for _, e := range os.Environ() { // N10(c): no GIT_* of the caller's, a hook's GIT_DIR included
		if !strings.HasPrefix(e, "GIT_") {
			env = append(env, e)
		}
	}
	cmd.Env = append(env, "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null", "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x.invalid", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x.invalid")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func openHost(t *testing.T, dir string) *host.Repo {
	t.Helper()
	r, err := host.Open(dir, dir, filepath.Join(dir, ".cache", "nohooks"))
	if err != nil {
		t.Fatal(err)
	}
	return r
}

// A, B: in a host with a tracker, the capture and tracker-only commands read and write the tracker, publish to the
// tracker's origin/main, and leave the host's tree, refs and config exactly as they were. The engine is the real one.
func TestTrackerCommandsWorkFromAHostAndLeaveItUntouched(t *testing.T) {
	t.Parallel()
	f, hostDir, bare := initHost(t)
	if code := run([]string{"init", bare}, f.d); code != 0 {
		t.Fatalf("init: exit %d: %s", code, f.errOut.String())
	}
	f.out.Reset()
	os.MkdirAll(filepath.Join(hostDir, "src"), 0o755)
	f.d.cwd = func() (string, error) { return filepath.Join(hostDir, "src"), nil }
	eng := realEngine(t, f)
	hostSnap, err := openHost(t, hostDir).Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	step := func(args ...string) string {
		t.Helper()
		f.out.Reset()
		f.errOut.Reset()
		if code := run(args, f.d); code != 0 || eng.code != 0 {
			t.Fatalf("zn %v: exit %d, engine %d\nstdout %s\nstderr %s", args, code, eng.code, f.out.String(), f.errOut.String())
		}
		if st := gitOut(t, hostDir, "status", "--porcelain"); st != "" {
			t.Errorf("zn %v: host status %q", args, st)
		}
		after, err := openHost(t, hostDir).Snapshot()
		if err != nil {
			t.Fatal(err)
		}
		if d := host.Diff(hostSnap, after); len(d) != 0 {
			t.Errorf("zn %v changed the host: %v", args, d)
		}
		return f.out.String()
	}
	out := step("new", "issue", "f", "first-thing", "--desc", "a first thing")
	m := regexp.MustCompile(`^/\S+/(up/\.tracker/issues/(f0001))/f0001\.md\n$`).FindStringSubmatch(out)
	if m == nil {
		t.Fatalf("new printed %q", out)
	}
	id, item := m[2], m[1]+"/"+m[2]+".md"
	if eng.dir != filepath.Join(hostDir, ".tracker", ".worktree", "zn") {
		t.Errorf("the engine ran in %s", eng.dir)
	}
	if !strings.Contains(strings.Join(eng.env, "\n")+"\n", "ZN_TOP="+eng.dir+"\n") {
		t.Errorf("ZN_TOP is not the standing worktree: %v", eng.env)
	}
	if files := gitOut(t, bare, "ls-tree", "-r", "--name-only", "main"); !strings.Contains(files, item) {
		t.Errorf("the tracker's main lacks the new ticket:\n%s", files)
	}
	if gitOut(t, bare, "log", "-1", "--format=%s", "main") == "" || gitOut(t, bare, "rev-list", "--count", "main") != "2" {
		t.Errorf("the tracker's main has %s commits, want the skeleton and the new ticket", gitOut(t, bare, "rev-list", "--count", "main"))
	}
	if out := step("list"); !strings.Contains(out, id) || !strings.Contains(out, "First thing") {
		t.Errorf("list: %q", out)
	}
	if out := step("audit"); !strings.Contains(out, "0 errors") {
		t.Errorf("audit: %q", out)
	}
	step("status", id)
	if out := step("guesses", id); !strings.Contains(out, id) {
		t.Errorf("guesses: %q", out)
	}
	// a second machine's view: another clone of the tracker lists the same ticket
	other := filepath.Join(resolved(t), "other")
	gitOut(t, filepath.Dir(other), "clone", "-q", bare, other)
	if !strings.Contains(gitOut(t, other, "ls-tree", "-r", "--name-only", "origin/main"), id) {
		t.Error("a fresh clone of the tracker does not hold the ticket")
	}
}

// A: where there is no tracker at the top (a plain repository, a repository like this one with tickets inside it, a
// folder outside every repository) the engine starts exactly as before: same program, same arguments, no folder
// change, no ZN_TOP or ZN_CWD of zn's own.
func TestWithNoTrackerTheEngineStartsAsBefore(t *testing.T) {
	t.Parallel()
	plain := resolved(t)
	gitOut(t, plain, "init", "-q", "-b", "main")
	like := resolved(t)
	gitOut(t, like, "init", "-q", "-b", "main")
	os.MkdirAll(filepath.Join(like, "z-nile", ".tracker", "issues"), 0o755)
	os.WriteFile(filepath.Join(like, "z-nile", "projects.toml"), []byte("x"), 0o644)
	for name, dir := range map[string]string{"plain": plain, "like pickman": like, "like pickman, inside": filepath.Join(like, "z-nile"), "outside": resolved(t)} {
		f := newFake(t, true)
		f.d.env = append(f.d.env, "ZN_CACHE="+filepath.Join(homeOf(f), "c"))
		f.d.cwd = func() (string, error) { return dir, nil }
		changed := ""
		f.d.chdir = func(d string) error { changed = d; return nil }
		if code := run([]string{"list", "--all"}, f.d); code != 0 || len(f.execs) != 1 {
			t.Fatalf("%s: exit %d, %d execs: %s", name, code, len(f.execs), f.errOut.String())
		}
		argv := f.execs[0].argv
		if len(argv) != 6 || argv[1] != "run" || argv[3] != "--" || argv[4] != "list" || argv[5] != "--all" {
			t.Errorf("%s: argv %q", name, argv)
		}
		if changed != "" {
			t.Errorf("%s: zn changed folder to %s", name, changed)
		}
		for _, e := range f.execs[0].env {
			if strings.HasPrefix(e, "ZN_TOP=") || strings.HasPrefix(e, "ZN_CWD=") {
				t.Errorf("%s: zn set %s", name, e)
			}
		}
	}
}

// C: a tracker that cannot be used stops the command before the engine starts, naming the cause (exit 4), and changes
// nothing; --help still prints.
func TestARefusedTrackerStopsBeforeTheEngine(t *testing.T) {
	t.Parallel()
	f, hostDir, bare := initHost(t)
	if code := run([]string{"init", bare}, f.d); code != 0 {
		t.Fatalf("init: %s", f.errOut.String())
	}
	tr := filepath.Join(hostDir, ".tracker")
	// round 3 (N4(a)): the registry is judged on the main Prepare fetched, so the removal is pushed, not only made local
	gitOut(t, tr, "rm", "-q", "z-nile/projects.toml")
	gitOut(t, tr, "commit", "-q", "-m", "drop it")
	gitOut(t, tr, "push", "-q", "origin", "HEAD:main")
	f = &fake{d: f.d}
	f.out.Reset()
	f.d.stdout, f.d.stderr = &f.out, &f.errOut
	realEngine(t, f) // a payload that holds the whole engine, so Prepare gets as far as the registry
	f.d.exec = func(path string, argv, env []string) error {
		f.execs = append(f.execs, execCall{path, argv, env})
		return nil
	}
	f.d.child = func(path string, argv, env []string, _, _ io.Writer) (int, error) {
		return 0, f.d.exec(path, argv, env)
	}
	f.d.chdir = func(string) error { t.Error("zn changed folder"); return nil }
	hostBefore, _ := openHost(t, hostDir).Snapshot()
	if code := run([]string{"list"}, f.d); code != exitRefused {
		t.Errorf("exit %d", code)
	}
	if len(f.execs) != 0 {
		t.Error("the engine started")
	}
	if !strings.Contains(f.errOut.String(), "z-nile/projects.toml") {
		t.Errorf("stderr %q does not name the missing registry", f.errOut.String())
	}
	if _, err := os.Lstat(filepath.Join(tr, ".worktree")); err == nil {
		t.Error("a refusal made a worktree")
	}
	after, _ := openHost(t, hostDir).Snapshot()
	if d := host.Diff(hostBefore, after); len(d) != 0 {
		t.Errorf("host changed: %v", d)
	}
	f.errOut.Reset()
	if code := run([]string{"--help"}, f.d); code != 0 || len(f.execs) != 1 {
		t.Errorf("--help: exit %d, %d execs", code, len(f.execs))
	}
}
