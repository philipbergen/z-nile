package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"znile/internal/fxtree"
	"znile/internal/host"
)

// A walkthrough with no address changes nothing, asks GitHub nothing and starts no engine.
func TestInitWithNoAddressPrintsTheWalkthroughAndChangesNothing(t *testing.T) {
	t.Parallel()
	f := newFake(t, true)
	dir := resolved(t)
	f.d.cwd = func() (string, error) { return dir, nil }
	f.d.lookup = func(host.RemoteID) (host.Facts, error) {
		t.Error("the walkthrough asked GitHub")
		return host.Facts{}, errors.New("no")
	}
	if code := run([]string{"init"}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	out := f.out.String()
	for _, want := range []string{"EMPTY", "no README", "gh repo create", "--public", "zn init <", "public", "never creates"} {
		if !strings.Contains(out, want) {
			t.Errorf("the walkthrough lacks %q:\n%s", want, out)
		}
	}
	if len(f.execs) != 0 {
		t.Error("init started the engine")
	}
	if ents, _ := os.ReadDir(dir); len(ents) != 0 {
		t.Errorf("the walkthrough wrote into the folder: %v", ents)
	}
	// the walkthrough is the same with flags: still nothing is done
	f2 := newFake(t, true)
	f2.d.cwd = f.d.cwd
	if code := run([]string{"init", "--gitignore"}, f2.d); code != 0 || !strings.Contains(f2.out.String(), "EMPTY") {
		t.Errorf("exit %d: %s", code, f2.out.String())
	}
}

func TestInitUsageErrors(t *testing.T) {
	t.Parallel()
	for _, args := range [][]string{{"init", "a", "b"}, {"init", "--nope"}, {"init", "--fork"}, {"init", "--upstream"}} {
		f := newFake(t, true)
		f.d.cwd = func() (string, error) { return resolved(t), nil }
		if code := run(args, f.d); code != exitUsage {
			t.Errorf("%v: exit %d, want %d", args, code, exitUsage)
		}
		if !strings.Contains(f.errOut.String(), "usage") {
			t.Errorf("%v: no usage in %q", args, f.errOut.String())
		}
	}
}

// initHost is a fixture host (a clone of a bare upstream) with an empty bare tracker, a throwaway HOME with an
// identity, and a lookup that says the user owns every repository.
func initHost(t *testing.T) (f *fake, hostDir, tracker string) {
	t.Helper()
	f = newFake(t, false)
	// c0179: the two bare repositories and the host's clone are built once per test binary (hostTemplate) and each test
	// gets its own copy of them, instead of running git init three times and a clone.
	tp := &hostTemplate
	tp.once.Do(func() {
		hostTemplateBuilds.Add(1)
		if tp.dir, tp.err = os.MkdirTemp("", "zn-host-template-"); tp.err != nil {
			return
		}
		if tp.dir, tp.err = filepath.EvalSymlinks(tp.dir); tp.err != nil {
			return
		}
		up, tr, h := filepath.Join(tp.dir, "up.git"), filepath.Join(tp.dir, "tracker.git"), filepath.Join(tp.dir, "host")
		for _, d := range []string{up, tr} {
			if tp.err = os.MkdirAll(d, 0o755); tp.err != nil {
				return
			}
		}
		// receive.unpackLimit in the bare remotes' own config only (not the host's, not HOME's): a push is kept as a pack
		for _, c := range [][]string{{up, "init", "-q", "--bare", "-b", "main"}, {tr, "init", "-q", "--bare", "-b", "main"}, {up, "config", "receive.unpackLimit", "1"}, {tr, "config", "receive.unpackLimit", "1"}, {tp.dir, "clone", "-q", up, h}} {
			if out, err := templateGit(c[0], c[1:]...); err != nil {
				tp.err = fmt.Errorf("git %v: %v\n%s", c[1:], err, out)
				return
			}
		}
	})
	if tp.err != nil || tp.dir == "" {
		t.Fatalf("the host template could not be built (%v): see the first test that built it", tp.err)
	}
	base := filepath.Join(resolved(t), "base")
	if err := fxtree.Copy(tp.dir, base); err != nil {
		t.Fatal(err)
	}
	// the clone's config names its origin by absolute path: point it at this copy
	cfg := filepath.Join(base, "host", ".git", "config")
	b, err := os.ReadFile(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(cfg, []byte(strings.ReplaceAll(string(b), tp.dir, base)), 0o644); err != nil {
		t.Fatal(err)
	}
	tracker, hostDir = filepath.Join(base, "tracker.git"), filepath.Join(base, "host")
	// the user's git identity is in the process-wide fixture HOME (TestMain), which no test writes: a parallel test sets
	// no variable
	f.d.cwd = func() (string, error) { return hostDir, nil }
	f.d.lookup = func(host.RemoteID) (host.Facts, error) { return host.Facts{CanPush: true, Owned: true}, nil }
	return f, hostDir, tracker
}

// initedHost is initHost after `zn init <tracker>` has succeeded, for the tests that need an initialised host as their
// starting point and not as what they test (hostWithEngine). The initialised host is built once per test binary
// (initedTemplate, by the real init) and each test gets its own copy, instead of running the init (a tracker clone, a
// skeleton commit and a push) again.
func initedHost(t *testing.T) (f *fake, hostDir, tracker string) {
	t.Helper()
	tp := &initedTemplate
	tp.once.Do(func() {
		f0, h0, tr0 := initHost(t)
		if code := run([]string{"init", tr0}, f0.d); code != 0 {
			tp.err = fmt.Errorf("init: exit %d: %s", code, f0.errOut.String())
			return
		}
		base := filepath.Dir(h0)
		if tp.dir, tp.err = os.MkdirTemp("", "zn-inited-template-"); tp.err != nil {
			return
		}
		if tp.dir, tp.err = filepath.EvalSymlinks(tp.dir); tp.err != nil {
			return
		}
		tp.base = base
		if tp.err = fxtree.Copy(base, filepath.Join(tp.dir, "base")); tp.err != nil {
			return
		}
		// every file that names the build folder must be one the copies rewrite: a new one would point a copy at the template
		tp.err = filepath.WalkDir(filepath.Join(tp.dir, "base"), func(p string, d fs.DirEntry, err error) error {
			if err != nil || !d.Type().IsRegular() {
				return err
			}
			if info, err := d.Info(); err != nil || info.Size() > 1<<20 {
				return err
			}
			b, err := os.ReadFile(p)
			rel, _ := filepath.Rel(filepath.Join(tp.dir, "base"), p)
			if err == nil && bytes.Contains(b, []byte(base)) && !initedConfigs[rel] {
				err = fmt.Errorf("%s names the template folder %s but is not one of the files a copy rewrites", rel, base)
			}
			return err
		})
	})
	if tp.err != nil || tp.dir == "" {
		t.Fatalf("the initialised host template could not be built (%v): see the first test that built it", tp.err)
	}
	f = newFake(t, false)
	copyBase := filepath.Join(resolved(t), "base")
	if err := fxtree.Copy(filepath.Join(tp.dir, "base"), copyBase); err != nil {
		t.Fatal(err)
	}
	for cfg := range initedConfigs {
		p := filepath.Join(copyBase, cfg)
		b, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(strings.ReplaceAll(string(b), tp.base, copyBase)), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	hostDir, tracker = filepath.Join(copyBase, "host"), filepath.Join(copyBase, "tracker.git")
	f.d.cwd = func() (string, error) { return hostDir, nil }
	f.d.lookup = func(host.RemoteID) (host.Facts, error) { return host.Facts{CanPush: true, Owned: true}, nil }
	return f, hostDir, tracker
}

// initedTemplate is initedHost's fixture; initedConfigs are the files of it that name its own folder, rewritten in a copy.
var initedTemplate struct {
	once      sync.Once
	dir, base string
	err       error
}

var initedConfigs = map[string]bool{"host/.git/config": true, "host/.tracker/.git/config": true}

// hostTemplateBuilds counts the builds of hostTemplate in this test binary: once (c0179).
var hostTemplateBuilds atomic.Int32

// The host template is built once per test binary and every initHost copies it ("template is built once per package").
func TestTheHostTemplateIsBuiltOncePerBinary(t *testing.T) {
	t.Parallel()
	for i := 0; i < 3; i++ {
		initHost(t)
	}
	if n := hostTemplateBuilds.Load(); n != 1 {
		t.Fatalf("the host template was built %d times in this binary, want once", n)
	}
}

// hostTemplate is initHost's fixture built once: the upstream and the tracker (bare, empty) and the host (a clone of the
// upstream), under dir, which TestMain removes.
var hostTemplate struct {
	once sync.Once
	dir  string
	err  error
}

// templateGit runs git in dir with the fixture's pins (no user or system config, the fixture template, an identity).
func templateGit(dir string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute) // bounded, like every process a test starts
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_TEMPLATE_DIR="+gitTemplate(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null", "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x.invalid", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x.invalid")
	return cmd.CombinedOutput()
}

// init is answered in Go even with no embedded engine: the first run prints its steps and does not say "already set
// up"; the second prints that and no step.
func TestInitRunsEndToEndInGo(t *testing.T) {
	t.Parallel()
	f, _, tracker := initHost(t)
	if code := run([]string{"init", tracker}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	if !strings.Contains(f.out.String(), "pushed main") || strings.Contains(f.out.String(), "already set up") {
		t.Errorf("first run stdout %q", f.out.String())
	}
	f.out.Reset()
	if code := run([]string{"init", tracker}, f.d); code != 0 || !strings.Contains(f.out.String(), "already set up") || strings.Contains(f.out.String(), "pushed") {
		t.Errorf("second run: exit %d, stdout %q", code, f.out.String())
	}
}

// The steps taken are printed before the error that stops init, and the error goes to stderr with the refusal code.
func TestInitPrintsTheStepsBeforeAnError(t *testing.T) {
	t.Parallel()
	f, _, tracker := initHost(t)
	hook := filepath.Join(tracker, "hooks", "pre-receive")
	os.WriteFile(hook, []byte("#!/bin/sh\nexit 1\n"), 0o755)
	if code := run([]string{"init", tracker}, f.d); code != exitRefused {
		t.Errorf("exit %d", code)
	}
	if !strings.Contains(f.out.String(), "cloned the tracker") || !strings.Contains(f.out.String(), "initialised") || strings.Contains(f.out.String(), "already set up") {
		t.Errorf("stdout %q", f.out.String())
	}
	if !strings.Contains(f.errOut.String(), "zn init:") || !strings.Contains(f.errOut.String(), "push") {
		t.Errorf("stderr %q", f.errOut.String())
	}
}

// A refusal exits with zn's refusal code, prints the cause on stderr, and never shows the secret in the address, in a
// real host (so the credential check itself is what refuses).
func TestInitRefusalExitsAndHidesTheSecret(t *testing.T) {
	t.Parallel()
	f, _, _ := initHost(t)
	code := run([]string{"init", "https://u:ghp_secretvalue@github.com/o/r.git"}, f.d)
	if code != exitRefused {
		t.Errorf("exit %d", code)
	}
	all := f.errOut.String() + f.out.String()
	if strings.Contains(all, "ghp_secretvalue") || strings.Contains(all, "u:") {
		t.Errorf("the output shows the credential: %s", all)
	}
	if !strings.Contains(f.errOut.String(), "credential") {
		t.Errorf("the credential check did not refuse: %q", f.errOut.String())
	}
}

// ghLookup: GitHub's answer for a repository, through an injected gh runner (no real gh in any test).
func TestGhLookup(t *testing.T) {
	t.Parallel()
	calls := 0
	runGH := func(args ...string) ([]byte, error) {
		calls++
		switch strings.Join(args, " ") {
		case "api --hostname github.com user":
			return []byte(`{"login":"Me"}`), nil
		case "api --hostname github.com repos/me/omarchy":
			return []byte(`{"parent":{"full_name":"basecamp/omarchy"},"permissions":{"push":true,"admin":true},"owner":{"login":"me","type":"User"}}`), nil
		case "api --hostname github.com repos/basecamp/omarchy":
			return []byte(`{"permissions":{"push":false,"admin":false},"owner":{"login":"basecamp","type":"Organization"}}`), nil
		case "api --hostname github.com repos/org/own":
			return []byte(`{"permissions":{"push":true,"admin":true},"owner":{"login":"org","type":"Organization"}}`), nil
		case "api --hostname github.com repos/o/expired":
			return nil, errors.New("gh api: HTTP 401: Bad credentials (https://api.github.com/repos/o/expired)")
		case "api --hostname github.com repos/o/signedout":
			return nil, errors.New("gh: To get started with GitHub CLI, please run:  gh auth login")
		}
		return nil, errors.New("HTTP 404: Not Found")
	}
	l := ghLookup(runGH)
	gh := func(o, r string) host.RemoteID { return host.RemoteID{Host: "github.com", Owner: o, Repo: r} }
	fa, err := l(gh("me", "omarchy"))
	if err != nil || fa.Parent == nil || fa.Parent.Owner != "basecamp" || !fa.CanPush || !fa.Owned {
		t.Errorf("fork: %+v %v", fa, err)
	}
	fa, err = l(gh("basecamp", "omarchy"))
	if err != nil || fa.Parent != nil || fa.CanPush || fa.Owned {
		t.Errorf("upstream: %+v %v", fa, err)
	}
	if fa, _ = l(gh("org", "own")); !fa.Owned {
		t.Errorf("an organisation repository the user administers is owned: %+v", fa)
	}
	if _, err := l(gh("o", "signedout")); !errors.Is(err, host.ErrNotSignedIn) {
		t.Errorf("signed out: %v", err)
	}
	if _, err := l(gh("o", "expired")); !errors.Is(err, host.ErrNotSignedIn) {
		t.Errorf("a 401: %v", err)
	}
	if _, err := l(gh("o", "missing")); err == nil || errors.Is(err, host.ErrNotSignedIn) || errors.Is(err, host.ErrNotServed) {
		t.Errorf("a 404 is an error of its own: %v", err)
	}
	if _, err := l(host.RemoteID{Host: "gitlab.example", Owner: "o", Repo: "r"}); !errors.Is(err, host.ErrNotServed) {
		t.Errorf("another forge: %v", err)
	}
	if _, err := l(host.RemoteID{Repo: "/a/b"}); !errors.Is(err, host.ErrNotServed) {
		t.Errorf("a local path: %v", err)
	}
	before := calls
	l(gh("me", "omarchy"))
	if calls-before > 2 {
		t.Errorf("%d gh calls for one repository", calls-before)
	}
}

// --project names the project in the tracker's registry, and a name the engine would refuse exits 4 with the reason.
func TestInitProjectOption(t *testing.T) {
	t.Parallel()
	f, _, tracker := initHost(t)
	if code := run([]string{"init", "--project", "mine", tracker}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	out, err := exec.Command("git", "-C", tracker, "show", "main:z-nile/projects.toml").Output()
	if err != nil || !strings.Contains(string(out), `name = "mine"`) {
		t.Errorf("registry %q %v", out, err)
	}
	g, _, tracker2 := initHost(t)
	if code := run([]string{"init", "--project=z-nile", tracker2}, g.d); code != exitRefused || !strings.Contains(g.errOut.String(), "reserved") {
		t.Errorf("exit %d, stderr %q", code, g.errOut.String())
	}
	if !strings.Contains(initUsage, "--project") || !strings.Contains(walkthrough, "--project") {
		t.Error("the usage and walkthrough must mention --project")
	}
	h := newFake(t, true)
	if code := run([]string{"init", "--project"}, h.d); code != exitUsage {
		t.Errorf("a bare --project: exit %d", code)
	}
}
