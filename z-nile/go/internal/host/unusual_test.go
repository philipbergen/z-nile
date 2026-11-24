package host

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// refusedAs asserts CheckHost refuses dir for exactly this reason and that the message names the cause.
func refusedAs(t *testing.T, dir string, want Reason, mention string) {
	t.Helper()
	err := CheckHost(dir)
	var u *UnusualHost
	if !errors.As(err, &u) {
		t.Fatalf("%s: want an UnusualHost refusal, got %v", want, err)
	}
	if u.Reason != want {
		t.Errorf("reason %q, want %q (%v)", u.Reason, want, err)
	}
	if !strings.Contains(err.Error(), mention) {
		t.Errorf("%s: the message %q does not name %q", want, err, mention)
	}
}

func TestCheckHostAcceptsAnOrdinaryClone(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	before := snap(t, f.open())
	if err := CheckHost(f.host); err != nil {
		t.Fatal(err)
	}
	if d := Diff(before, snap(t, f.open())); len(d) != 0 {
		t.Errorf("the check wrote: %v", d)
	}
	// ignored and untracked folders of zn are fine: only a tracked path is refused
	for _, d := range []string{".tracker", ".worktree", ".cache"} {
		if err := os.MkdirAll(filepath.Join(f.host, d, "x"), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(f.host, d, "x", "f"), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if err := CheckHost(f.host); err != nil {
		t.Errorf("untracked zn folders refused: %v", err)
	}
}

// stopWalkAt keeps the enclosing-repository walk inside the test's own temp folder, so the tests do not depend on
// whether TMPDIR sits inside a git repository.
func stopWalkAt(t *testing.T, dir string) {
	t.Helper()
	old := walkStop
	walkStop = dir
	t.Cleanup(func() { walkStop = old })
}

func TestCheckHostNotARepository(t *testing.T) {
	t.Parallel()
	base := realTemp(t)
	stopWalkAt(t, base)
	d := filepath.Join(base, "plain")
	if err := os.MkdirAll(d, 0o755); err != nil {
		t.Fatal(err)
	}
	refusedAs(t, d, ReasonNotRepo, "not a git repository")
	refusedAs(t, filepath.Join(d, "missing"), ReasonNotRepo, "missing")
}

func TestCheckHostSubmodule(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	sub := filepath.Join(f.host, "vendor", "sub")
	run(t, f.host, "-c", "protocol.file.allow=always", "submodule", "add", "-q", f.seed, "vendor/sub")
	// the submodule's own folder has a gitfile too: the submodule reason must win
	refusedAs(t, sub, ReasonSubmodule, "submodule")
	// and the superproject is an ordinary host
	if err := CheckHost(f.host); err != nil {
		t.Errorf("the superproject refused: %v", err)
	}
}

func TestCheckHostGitfiles(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	wt := filepath.Join(f.base, "linked")
	run(t, f.host, "worktree", "add", "-q", "-b", "side", wt)
	refusedAs(t, wt, ReasonGitfile, "main checkout")
	sep := filepath.Join(f.base, "sep")
	run(t, f.base, "clone", "-q", "--separate-git-dir", filepath.Join(f.base, "sep.gitdir"), f.upstream, sep)
	refusedAs(t, sep, ReasonGitfile, "main checkout")
}

func TestCheckHostBare(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	refusedAs(t, f.upstream, ReasonBare, "bare")
	run(t, f.upstream, "worktree", "add", "-q", "-b", "side", filepath.Join(f.base, "bare-wt"))
	refusedAs(t, f.upstream, ReasonBare, "bare")
}

func TestCheckHostNotTopLevel(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	sub := filepath.Join(f.host, "deep", "er")
	if err := os.MkdirAll(sub, 0o755); err != nil {
		t.Fatal(err)
	}
	refusedAs(t, sub, ReasonNotTop, f.host)
	refusedAs(t, f.host+"/.git", ReasonNotTop, "top level")
	// a symlink to the top level is the top level
	link := filepath.Join(f.base, "link")
	if err := os.Symlink(f.host, link); err != nil {
		t.Fatal(err)
	}
	if err := CheckHost(link); err != nil {
		t.Errorf("a symlink to the top level refused: %v", err)
	}
}

// F15: a folder under a dotfiles repository in $HOME is not told to use $HOME.
func TestCheckHostIgnoresARepositoryInTheUsersHome(t *testing.T) {
	home := realTemp(t)
	stopWalkAt(t, filepath.Dir(home))
	run(t, home, "init", "-q", "-b", "main")
	proj := filepath.Join(home, "code", "proj")
	if err := os.MkdirAll(proj, 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	err := CheckHost(proj)
	var u *UnusualHost
	if !errors.As(err, &u) || u.Reason != ReasonNotRepo {
		t.Fatalf("got %v, want %s", err, ReasonNotRepo)
	}
	if strings.Contains(err.Error(), "use that folder") {
		t.Errorf("the message sends the user to the repository in their home: %v", err)
	}
}

// F1: the host's own local config can name a program; reads must never run it.
func plantFsmonitor(t *testing.T, f *fixture) string {
	t.Helper()
	marker := filepath.Join(f.base, "fsmonitor-ran")
	script := filepath.Join(f.base, "fsmonitor.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\ntouch \""+marker+"\"\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	run(t, f.host, "config", "core.fsmonitor", script)
	return marker
}

func noMarker(t *testing.T, marker, what string) {
	t.Helper()
	if _, err := os.Stat(marker); err == nil {
		t.Fatalf("%s ran the host's core.fsmonitor program", what)
	}
}

func TestReadsNeverRunTheHostsFsmonitor(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	marker := plantFsmonitor(t, f)
	r := f.open()
	if _, err := r.readGit("status", "--porcelain"); err != nil {
		t.Fatal(err)
	}
	if _, err := r.readGit("ls-files"); err != nil {
		t.Fatal(err)
	}
	noMarker(t, marker, "a read")
	if _, err := r.Snapshot(); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Remotes(); err != nil {
		t.Fatal(err)
	}
	noMarker(t, marker, "Snapshot or Remotes")
}

func TestCheckHostNeverRunsTheHostsFsmonitor(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	marker := plantFsmonitor(t, f)
	refusedAs(t, f.host, ReasonLocalConfig, "core.fsmonitor")
	noMarker(t, marker, "CheckHost")
}

// F12: init must refuse before it writes anything: a local config the write allowlist refuses is a reason.
func TestCheckHostRefusesLocalConfigTheWritesWouldRefuse(t *testing.T) {
	t.Parallel()
	for _, kv := range [][2]string{
		{"core.sparseCheckout", "true"}, {"remote.origin.promisor", "true"}, {"remote.origin.partialclonefilter", "blob:none"},
		{"core.sshCommand", "touch /x/never-secret-value"}, {"include.path", "../x"}, {"extensions.partialclone", "origin"},
	} {
		f := newFixture(t)
		run(t, f.host, "config", kv[0], kv[1])
		before := snap(t, f.open())
		err := CheckHost(f.host)
		var u *UnusualHost
		if !errors.As(err, &u) || u.Reason != ReasonLocalConfig {
			t.Errorf("%s: got %v, want %s", kv[0], err, ReasonLocalConfig)
			continue
		}
		if !strings.Contains(strings.ToLower(err.Error()), strings.ToLower(kv[0])) || strings.Contains(err.Error(), kv[1]) {
			t.Errorf("%s: the message must name the key and not its value: %v", kv[0], err)
		}
		if d := Diff(before, snap(t, f.open())); len(d) != 0 {
			t.Errorf("%s: the check wrote: %v", kv[0], d)
		}
	}
}

// F12: a tracked .Tracker collides with the clone on a case-insensitive file system.
func TestCheckHostTrackedNamesDifferingInCase(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	run(t, f.host, "config", "core.ignorecase", "true")
	if err := os.MkdirAll(filepath.Join(f.host, ".Tracker"), 0o755); err != nil {
		t.Fatal(err)
	}
	commit(t, f.host, filepath.Join(".Tracker", "x"))
	refusedAs(t, f.host, ReasonTracked, ".Tracker")
	run(t, f.host, "config", "core.ignorecase", "false")
	if err := CheckHost(f.host); err != nil {
		t.Errorf("on a case-sensitive file system a different name is a different name: %v", err)
	}
}

// F12: the base commit a worktree starts from must not track those paths either.
func TestCheckBase(t *testing.T) {
	t.Parallel()
	for _, name := range []string{".tracker", ".worktree", ".cache", ".Tracker"} {
		f := newFixture(t)
		if err := os.MkdirAll(filepath.Join(f.seed, name), 0o755); err != nil {
			t.Fatal(err)
		}
		commit(t, f.seed, filepath.Join(name, "x"))
		run(t, f.seed, "push", "-q", "origin", "main")
		r := f.open()
		if err := r.CheckBase("refs/remotes/origin/main"); err != nil {
			t.Fatalf("%s: before the fetch the base is the old one: %v", name, err)
		}
		if err := r.FetchDefault("origin", "main"); err != nil {
			t.Fatal(err)
		}
		before := snap(t, r)
		err := r.CheckBase("refs/remotes/origin/main")
		var u *UnusualHost
		if !errors.As(err, &u) || u.Reason != ReasonTracked || !strings.Contains(err.Error(), name) {
			t.Errorf("%s: got %v", name, err)
		}
		if d := Diff(before, snap(t, r)); len(d) != 0 {
			t.Errorf("%s: the check wrote: %v", name, d)
		}
		wt := filepath.Join(f.host, ".worktree", "R0001")
		if err := r.AddWorktree(wt, branch, "refs/remotes/origin/main"); err == nil {
			t.Errorf("%s: a worktree was added on a base that tracks it", name)
		}
		if _, err := os.Stat(wt); err == nil {
			t.Errorf("%s: the worktree exists", name)
		}
	}
	f := newFixture(t)
	r := f.open()
	if err := r.CheckBase("-x"); err == nil {
		t.Error("an option-like base was accepted")
	}
	if err := r.CheckBase("refs/remotes/origin/nothing"); err == nil {
		t.Error("a missing base was accepted")
	}
	if err := r.CheckBase("origin/main"); err != nil {
		t.Errorf("an ordinary base refused: %v", err)
	}
}
func TestCheckHostTrackedZnFolders(t *testing.T) {
	t.Parallel()
	for _, name := range []string{".tracker", ".worktree", ".cache"} {
		f := newFixture(t)
		if err := os.MkdirAll(filepath.Join(f.host, name, "deep"), 0o755); err != nil {
			t.Fatal(err)
		}
		commit(t, f.host, filepath.Join(name, "deep", "file"))
		before := snap(t, f.open())
		refusedAs(t, f.host, ReasonTracked, name)
		if d := Diff(before, snap(t, f.open())); len(d) != 0 {
			t.Errorf("%s: the check wrote: %v", name, d)
		}
	}
}

func TestCheckHostSimilarNamesAreNotTheZnFolders(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	for _, n := range []string{".tracker2", "x/.tracker", ".cachefile", ".worktrees"} {
		if err := os.MkdirAll(filepath.Join(f.host, filepath.Dir(n)), 0o755); err != nil {
			t.Fatal(err)
		}
		commit(t, f.host, n)
	}
	if err := CheckHost(f.host); err != nil {
		t.Errorf("refused: %v", err)
	}
}

func TestCheckHostDoesNotAddAShallowReason(t *testing.T) {
	t.Parallel()
	// the design names no shallow-clone refusal, so a shallow clone is an ordinary host
	f := newFixture(t)
	sh := filepath.Join(f.base, "shallow")
	run(t, f.base, "clone", "-q", "--depth", "1", "file://"+f.upstream, sh)
	if err := CheckHost(sh); err != nil {
		t.Errorf("a shallow clone was refused: %v", err)
	}
}

// round 2 item 6: the walk for an enclosing repository stops at the seam, and finds one otherwise
func TestCheckHostEnclosingWalkStopsAtTheSeam(t *testing.T) {
	t.Parallel()
	base := realTemp(t)
	outer := filepath.Join(base, "outer")
	work := filepath.Join(outer, "inner", "work")
	if err := os.MkdirAll(filepath.Join(outer, ".git"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(work, 0o755); err != nil {
		t.Fatal(err)
	}
	stopWalkAt(t, "")
	refusedAs(t, work, ReasonNotTop, outer)
	stopWalkAt(t, filepath.Join(outer, "inner"))
	refusedAs(t, work, ReasonNotRepo, "not a git repository")
}

// round 2 item 5: CheckHost judges the directory it was given, whatever git's own environment variables say
func TestCheckHostIgnoresGitEnvironment(t *testing.T) {
	f := newFixture(t)
	other := newFixture(t)
	t.Setenv("GIT_DIR", filepath.Join(other.host, ".git"))
	t.Setenv("GIT_WORK_TREE", other.host)
	if err := CheckHost(f.host); err != nil {
		t.Errorf("a host was judged by the environment's repository: %v", err)
	}
	plain := filepath.Join(realTemp(t), "plain")
	if err := os.MkdirAll(plain, 0o755); err != nil {
		t.Fatal(err)
	}
	stopWalkAt(t, filepath.Dir(plain))
	refusedAs(t, plain, ReasonNotRepo, "not a git repository")
}
