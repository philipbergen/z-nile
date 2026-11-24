package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
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
	// cacheDir is the ZN_CACHE the payload is extracted under (round 5: a test runs the engine itself from there)
	cacheDir string
}

// engineTemplate is the real engine packed and extracted once, through the product: its payload, the Lune bytes, and under dir
// a cache folder holding what `zn` extracted, exactly as it lays it out. Every folder of it is then made read-only (0500),
// so a test that tries to create, rename or delete there fails in that test, and each real-engine test checks its digest
// when it ends (a test that wrote the shared cache is named). TestMain restores the modes and removes dir.
var engineTemplate engineTpl

type engineTpl struct {
	once sync.Once
	dir  string
	lune []byte
	p    payload.Payload
	// digest is treeDigest of dir/cache when it was made
	digest string
	err    error
}

func buildEngineTemplate(t *testing.T, tp *engineTpl, root, lune string) {
	var err error
	if tp.lune, err = os.ReadFile(lune); err != nil {
		tp.err = err
		return
	}
	var tarBuf bytes.Buffer
	if _, err := payload.Pack(root, []string{"z-nile/engine", "z-nile/lib", "z-nile/vendor", "z-nile/templates", "z-nile/roots.luau", "z-nile/affected.luau"}, &tarBuf); err != nil {
		tp.err = err
		return
	}
	tp.p = payload.New(tp.lune, tarBuf.Bytes(), "kind bin\n")
	if tp.dir, tp.err = os.MkdirTemp("", "zn-engine-template-"); tp.err != nil {
		return
	}
	if tp.dir, tp.err = filepath.EvalSymlinks(tp.dir); tp.err != nil {
		return
	}
	cache := filepath.Join(tp.dir, "cache")
	// the real extraction, through the product: one `zn --help` against an empty cache, with the engine start left out
	f := newFake(t, false)
	p := tp.p
	f.d.embedded = func() (payload.Payload, bool) { return p, true }
	f.d.env = append(f.d.env, "ZN_CACHE="+cache)
	here := tp.dir
	f.d.cwd = func() (string, error) { return here, nil }
	f.d.exec = func(string, []string, []string) error { return nil }
	f.d.child = func(string, []string, []string, io.Writer, io.Writer) (int, error) { return 0, nil }
	if code := run([]string{"--help"}, f.d); code != 0 {
		tp.err = fmt.Errorf("zn --help against the empty template cache: exit %d: %s", code, f.errOut.String())
		return
	}
	if luns, _ := filepath.Glob(filepath.Join(cache, "zn", "*", "bin", "lune")); len(luns) != 1 {
		tp.err = fmt.Errorf("zn extracted %d payloads into the template cache, want 1", len(luns))
		return
	}
	var dirs []string
	filepath.WalkDir(cache, func(p string, d fs.DirEntry, err error) error {
		if err == nil && d.IsDir() {
			dirs = append(dirs, p)
		}
		return nil
	})
	if tp.digest, err = treeDigest(cache); err != nil {
		tp.err = err
		return
	}
	for i := len(dirs) - 1; i >= 0; i-- { // children first, so every chmod still reaches its folder
		if err := os.Chmod(dirs[i], 0o500); err != nil {
			tp.err = err
			return
		}
	}
	if d, err := treeDigest(cache); err == nil {
		tp.digest = d // the folders' new modes are part of what must not change
	}
}

// treeDigest is a hash of every path, mode, size and content under dir: equal digests mean nothing changed.
func treeDigest(dir string) (string, error) {
	h := sha256.New()
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(dir, p)
		fmt.Fprintf(h, "%s %v %d\n", rel, info.Mode(), info.Size())
		if info.Mode().IsRegular() {
			b, err := os.ReadFile(p)
			if err != nil {
				return err
			}
			h.Write(b)
		}
		return nil
	})
	return fmt.Sprintf("%x", h.Sum(nil)), err
}

// engineFor is the template (built on the first call) and the Lune it was made with, or a skip or failure when there is no
// pinned Lune.
func engineFor(t *testing.T) *engineTpl {
	t.Helper()
	lune, ok := findLune()
	if !ok {
		if luneMissingIsFatal(os.Getenv) {
			t.Fatal("no Lune that matches cmd/zn/lune.sum was found, and under the gate a real-engine test may not skip")
		}
		t.Skip("no Lune that matches cmd/zn/lune.sum was found: the test will not run an unverified binary")
	}
	root := engineRoot(t)
	tp := &engineTemplate
	tp.once.Do(func() { buildEngineTemplate(t, tp, root, lune) })
	if tp.err != nil {
		t.Fatalf("the engine template could not be built (%v): see the first test that built it", tp.err)
	}
	return tp
}

// realEngine is realEngineIn the cache every real-engine test shares, which zn finds complete and runs from: it extracts
// nothing and the folders are read-only. A test that changed the cache is named when it ends.
func realEngine(t *testing.T, f *fake) *engineRun {
	t.Helper()
	tp := engineFor(t)
	cache := filepath.Join(tp.dir, "cache")
	t.Cleanup(func() {
		if d, err := treeDigest(cache); err != nil || d != tp.digest {
			t.Errorf("this test changed the extracted engine cache the real-engine tests share (%v)", err)
		}
	})
	return realEngineIn(t, f, cache)
}

// realEngineIn puts the real Lune and this checkout's engine into the fake's payload with ZN_CACHE at cache, and lets its
// exec run the engine as a child (a real exec would replace the test).
func realEngineIn(t *testing.T, f *fake, cache string) *engineRun {
	t.Helper()
	tp := engineFor(t)
	luneBytes, p := tp.lune, tp.p
	f.d.embedded = func() (payload.Payload, bool) { return p, true }
	f.d.env = append(f.d.env, "ZN_CACHE="+cache, "ZN_ENGINE_CPU=600")
	r := &engineRun{cacheDir: cache}
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
	cmd.Env = append(env, "GIT_TEMPLATE_DIR="+gitTemplate, "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null", "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x.invalid", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x.invalid")
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
