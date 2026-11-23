package main

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"znile/internal/host"
)

// A walkthrough with no address changes nothing, asks GitHub nothing and starts no engine.
func TestInitWithNoAddressPrintsTheWalkthroughAndChangesNothing(t *testing.T) {
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
	base := resolved(t)
	g := func(dir string, args ...string) {
		t.Helper()
		cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null", "GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@x.invalid", "GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@x.invalid")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	up := filepath.Join(base, "up.git")
	tracker, hostDir = filepath.Join(base, "tracker.git"), filepath.Join(base, "host")
	os.MkdirAll(up, 0o755)
	os.MkdirAll(tracker, 0o755)
	g(up, "init", "-q", "--bare", "-b", "main")
	g(tracker, "init", "-q", "--bare", "-b", "main")
	g(base, "clone", "-q", up, hostDir)
	home := resolved(t)
	os.WriteFile(filepath.Join(home, ".gitconfig"), []byte("[user]\n\tname = T\n\temail = t@users.noreply.github.com\n"), 0o644)
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	f.d.cwd = func() (string, error) { return hostDir, nil }
	f.d.lookup = func(host.RemoteID) (host.Facts, error) { return host.Facts{CanPush: true, Owned: true}, nil }
	return f, hostDir, tracker
}

// init is answered in Go even with no embedded engine: the first run prints its steps and does not say "already set
// up"; the second prints that and no step.
func TestInitRunsEndToEndInGo(t *testing.T) {
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
