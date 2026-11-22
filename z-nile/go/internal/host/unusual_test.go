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

func TestCheckHostNotARepository(t *testing.T) {
	d := filepath.Join(realTemp(t), "plain")
	if err := os.MkdirAll(d, 0o755); err != nil {
		t.Fatal(err)
	}
	refusedAs(t, d, ReasonNotRepo, "not a git repository")
	refusedAs(t, filepath.Join(d, "missing"), ReasonNotRepo, "missing")
}

func TestCheckHostSubmodule(t *testing.T) {
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
	f := newFixture(t)
	wt := filepath.Join(f.base, "linked")
	run(t, f.host, "worktree", "add", "-q", "-b", "side", wt)
	refusedAs(t, wt, ReasonGitfile, "main checkout")
	sep := filepath.Join(f.base, "sep")
	run(t, f.base, "clone", "-q", "--separate-git-dir", filepath.Join(f.base, "sep.gitdir"), f.upstream, sep)
	refusedAs(t, sep, ReasonGitfile, "main checkout")
}

func TestCheckHostBare(t *testing.T) {
	f := newFixture(t)
	refusedAs(t, f.upstream, ReasonBare, "bare")
	run(t, f.upstream, "worktree", "add", "-q", "-b", "side", filepath.Join(f.base, "bare-wt"))
	refusedAs(t, f.upstream, ReasonBare, "bare")
}

func TestCheckHostNotTopLevel(t *testing.T) {
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

func TestCheckHostTrackedZnFolders(t *testing.T) {
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
	// the design names no shallow-clone refusal, so a shallow clone is an ordinary host
	f := newFixture(t)
	sh := filepath.Join(f.base, "shallow")
	run(t, f.base, "clone", "-q", "--depth", "1", "file://"+f.upstream, sh)
	if err := CheckHost(sh); err != nil {
		t.Errorf("a shallow clone was refused: %v", err)
	}
}
