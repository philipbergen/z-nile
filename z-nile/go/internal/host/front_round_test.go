package host

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"testing"
	"time"
)

// The second review round of f0428 step 4: each test names the item it guards.

// exclude adds lines to the tracker's own info/exclude, so a file made there by hand is ignored and only zn's own
// checks can see it (git status cannot).
func (f *frontFixture) exclude(t *testing.T, lines ...string) {
	t.Helper()
	p := filepath.Join(f.tracker_(), ".git", "info", "exclude")
	b, _ := os.ReadFile(p)
	if err := os.WriteFile(p, append(b, []byte("\n"+strings.Join(lines, "\n")+"\n")...), 0o644); err != nil {
		t.Fatal(err)
	}
}

// B: a tracker's tree holds data only. A link or a submodule anywhere, anything under z-nile/ but the registry, the
// counter and the compaction map, and the paths that Lune, a model CLI or zn read as code (at or under, in any case)
// are refused, naming the path; removing it from the tracker's main is the way out.
func TestTheTrackerTreeIsDataOnly(t *testing.T) {
	cases := []struct {
		name  string
		files map[string]*string
		links map[string]string
		want  string
	}{
		{"a link to the host", nil, map[string]string{"upstream/.tracker/issues/f0001": "../../../.."}, "upstream/.tracker/issues/f0001"},
		{"any link", nil, map[string]string{"notes.md": "README.md"}, "notes.md"},
		{"a folder that wins over roots.luau", map[string]*string{"z-nile/roots/init.luau": str("x")}, nil, "z-nile/roots/init.luau"},
		{"a file beside the registry", map[string]*string{"z-nile/x.luau": str("x")}, nil, "z-nile/x.luau"},
		{"a .luaurc in z-nile", map[string]*string{"z-nile/.luaurc": str("{}")}, nil, "z-nile/.luaurc"},
		{"a Lune script folder", map[string]*string{".lune/x.luau": str("x")}, nil, ".lune/x.luau"},
		{"a plain Lune script folder", map[string]*string{"lune/x.luau": str("x")}, nil, "lune/x.luau"},
		{"a Luau config", map[string]*string{".config.luau": str("x")}, nil, ".config.luau"},
		{"a model table", map[string]*string{".models.toml": str("x")}, nil, ".models.toml"},
		{"a cache", map[string]*string{".cache/x": str("x")}, nil, ".cache/x"},
		{"a worktree folder", map[string]*string{".worktree/x": str("x")}, nil, ".worktree/x"},
		{"scripts", map[string]*string{"scripts/hooks/pre-bash.sh": str("x")}, nil, "scripts/hooks/pre-bash.sh"},
		{"another case of AGENTS.md", map[string]*string{"Agents.md": str("x")}, nil, "Agents.md"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := newFrontFixture(t)
			tr := f.located(t)
			before := hostTree(t, f.host)
			f.pushFrom(t, c.files, c.links)
			_, err := tr.Prepare(f.payload)
			refusal(t, err, ReasonCodeInTracker, c.want)
			sameTree(t, "the host", before, hostTree(t, f.host))
			if _, e := os.Lstat(filepath.Join(f.standing(), c.want)); e == nil {
				t.Errorf("%s was checked out", c.want)
			}
			gone := map[string]*string{}
			for p := range c.files {
				gone[p] = nil
			}
			for p := range c.links {
				gone[p] = nil
			}
			f.pushFrom(t, gone, nil) // the way out
			if _, err := tr.Prepare(f.payload); err != nil {
				t.Errorf("after removing it: %v", err)
			}
		})
	}
	// entries a case-insensitive disk could not make by hand: put straight into the index of another clone
	for _, c := range []struct{ name, mode, path string }{
		{"a submodule", "160000", "vendored"},
		{"another case of z-nile", "100644", "Z-Nile/engine/x.luau"},
		{"another case of .claude", "100644", ".CLAUDE/settings.json"},
	} {
		t.Run(c.name, func(t *testing.T) {
			f := newFrontFixture(t)
			tr := f.located(t)
			other := filepath.Join(f.base, "index-clone")
			run(t, f.base, "clone", "-q", f.tracker, other)
			obj := run(t, other, "rev-parse", "HEAD")
			if c.mode != "160000" {
				os.WriteFile(filepath.Join(f.base, "blob"), []byte("x"), 0o644)
				obj = run(t, other, "hash-object", "-w", filepath.Join(f.base, "blob"))
			}
			run(t, other, "update-index", "--add", "--cacheinfo", c.mode+","+obj+","+c.path)
			run(t, other, "commit", "-q", "-m", "entry")
			run(t, other, "push", "-q", "origin", "main")
			_, err := tr.Prepare(f.payload)
			refusal(t, err, ReasonCodeInTracker, c.path)
		})
	}
	t.Run("the data files are data", func(t *testing.T) {
		f := newFrontFixture(t)
		tr := f.located(t)
		f.pushFrom(t, map[string]*string{"z-nile/compaction.txt": str(""), "upstream/.tracker/issues/f0001/f0001.md": str("# x\n")}, nil)
		if _, err := tr.Prepare(f.payload); err != nil {
			t.Error(err)
		}
	})
}

// B: the tracker's main checkout is judged by what it holds, not only by origin/main: a local commit there that adds
// code is refused before anything runs.
func TestTheTrackersOwnCheckoutHoldsNoCode(t *testing.T) {
	f := newFrontFixture(t)
	os.WriteFile(filepath.Join(f.tracker_(), "zn"), []byte("#!/bin/sh\n"), 0o755)
	run(t, f.tracker_(), "add", "zn")
	run(t, f.tracker_(), "commit", "-q", "-m", "a wrapper")
	tr, err := Locate(f.host)
	if tr != nil {
		t.Fatalf("located %v", tr)
	}
	refusal(t, err, ReasonCodeInTracker, "zn")
}

// B: a file at a path zn owns is refused even when git cannot see it (ignored), in the tracker's checkout and in the
// worktree the engine runs in.
func TestAnIgnoredFileAtAPathZnOwnsIsRefused(t *testing.T) {
	for _, c := range []struct{ where, path, named string }{
		{"tracker", "AGENTS.md", "AGENTS.md"}, {"tracker", ".claude/settings.json", ".claude"}, {"standing", ".luaurc", ".luaurc"},
		{"standing", "zn", "zn"}, {"standing", "z-nile/.luaurc", "z-nile/.luaurc"}, {"standing", "z-nile/bin/git", "z-nile/bin"},
	} {
		t.Run(c.where+" "+c.path, func(t *testing.T) {
			f := newFrontFixture(t)
			tr := f.located(t)
			if _, err := tr.Prepare(f.payload); err != nil {
				t.Fatal(err)
			}
			f.exclude(t, "/"+c.path)
			root := f.tracker_()
			if c.where == "standing" {
				root = f.standing()
			}
			p := filepath.Join(root, c.path)
			os.MkdirAll(filepath.Dir(p), 0o755)
			os.WriteFile(p, []byte("x"), 0o755)
			tr2, err := Locate(f.host)
			if err == nil {
				_, err = tr2.Prepare(f.payload)
			}
			refusal(t, err, ReasonCodeInTracker, filepath.Join(root, c.named))
		})
	}
}

// C: no folder zn writes through is a link: the worktree folder, the standing worktree's cache folder, the tracker's
// info folder and its lock. Each is refused and nothing is written where the link points.
func TestNoComponentZnWritesThroughIsALink(t *testing.T) {
	t.Run(".worktree", func(t *testing.T) {
		f := newFrontFixture(t)
		tr := f.located(t)
		inside := filepath.Join(f.tracker_(), "upstream")
		f.exclude(t, "/.worktree")
		os.Symlink(inside, filepath.Join(f.tracker_(), ".worktree"))
		before := tree(t, inside)
		_, err := tr.Prepare(f.payload)
		refusal(t, err, ReasonWorktree, filepath.Join(f.tracker_(), ".worktree"))
		sameTree(t, "the link's target", before, tree(t, inside))
	})
	t.Run("the standing worktree's .cache", func(t *testing.T) {
		f := newFrontFixture(t)
		tr := f.located(t)
		if _, err := tr.Prepare(f.payload); err != nil {
			t.Fatal(err)
		}
		f.exclude(t, "/.cache")
		os.RemoveAll(filepath.Join(f.standing(), ".cache"))
		os.Symlink(f.host, filepath.Join(f.standing(), ".cache"))
		_, err := tr.Prepare(f.payload)
		refusal(t, err, ReasonWorktree, filepath.Join(f.standing(), ".cache"))
	})
	t.Run(".git/info", func(t *testing.T) {
		f := newFrontFixture(t)
		tr := f.located(t)
		elsewhere := realTemp(t)
		info := filepath.Join(f.tracker_(), ".git", "info")
		os.Rename(info, filepath.Join(elsewhere, "info"))
		os.Symlink(filepath.Join(elsewhere, "info"), info)
		before := tree(t, elsewhere)
		if _, err := tr.Prepare(f.payload); err == nil {
			t.Error("a linked .git/info was written through")
		}
		sameTree(t, "the link's target", before, tree(t, elsewhere))
	})
	t.Run("the lock", func(t *testing.T) {
		f := newFrontFixture(t)
		target := filepath.Join(f.base, "victim")
		os.WriteFile(target, []byte("keep"), 0o644)
		os.Symlink(target, filepath.Join(f.tracker_(), ".git", "zn.lock"))
		if l, err := LockTracker(f.tracker_(), time.Second); err == nil {
			l.Release()
			t.Error("the lock was taken through a link")
		}
		if got := readText(t, target); got != "keep" {
			t.Errorf("the link's target was written: %q", got)
		}
	})
}

// H: the push address is checked last, in the worktree the engine pushes from, so a pushurl in that worktree's own
// config (extensions.worktreeConfig) is refused without showing it.
func TestAPushAddressInTheWorktreesOwnConfigIsRefused(t *testing.T) {
	f := newFrontFixture(t)
	tr := f.located(t)
	run(t, f.tracker_(), "config", "extensions.worktreeConfig", "true")
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	other := filepath.Join(f.base, "elsewhere-secret.git")
	os.MkdirAll(other, 0o755)
	run(t, other, "init", "-q", "--bare")
	run(t, f.standing(), "config", "--worktree", "remote.origin.pushurl", other)
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonAddress, "origin")
	if strings.Contains(err.Error(), "elsewhere-secret") {
		t.Errorf("the address is shown: %v", err)
	}
	// a program-running key in that config is refused too
	run(t, f.standing(), "config", "--worktree", "--unset", "remote.origin.pushurl")
	run(t, f.standing(), "config", "--worktree", "core.hooksPath", filepath.Join(f.standing(), "upstream"))
	if _, err := tr.Prepare(f.payload); err == nil || !strings.Contains(err.Error(), "core.hookspath") {
		t.Errorf("a hooksPath in the worktree's config: %v", err)
	}
}

// J: each malformed layout is refused by Locate, naming the cause, with nothing written.
func TestLocateRefusesEachMalformedLayout(t *testing.T) {
	cases := []struct {
		name   string
		break_ func(t *testing.T, f *frontFixture) string // returns the folder to run from
		reason TrackerReason
	}{
		{".tracker is a file", func(t *testing.T, f *frontFixture) string {
			os.RemoveAll(f.tracker_())
			os.WriteFile(f.tracker_(), []byte("x"), 0o644)
			return f.host
		}, ReasonTrackerLink},
		{".tracker has a separate git directory", func(t *testing.T, f *frontFixture) string {
			os.RemoveAll(f.tracker_())
			run(t, f.base, "clone", "-q", "--separate-git-dir="+filepath.Join(f.base, "sep.git"), f.tracker, f.tracker_())
			return f.host
		}, ReasonNotClone},
		{".tracker is a worktree of the host", func(t *testing.T, f *frontFixture) string {
			os.RemoveAll(f.tracker_())
			run(t, f.host, "worktree", "add", "-q", "--detach", f.tracker_())
			return f.host
		}, ReasonNotClone},
		{".tracker/.git is a link", func(t *testing.T, f *frontFixture) string {
			g := filepath.Join(f.tracker_(), ".git")
			os.Rename(g, filepath.Join(f.base, "moved.git"))
			os.Symlink(filepath.Join(f.base, "moved.git"), g)
			return f.host
		}, ReasonNotClone},
		{"the tracker's config runs a program", func(t *testing.T, f *frontFixture) string {
			run(t, f.tracker_(), "config", "core.fsmonitor", "true")
			return f.host
		}, ReasonNotClone},
		{"inside the tracker's git directory", func(t *testing.T, f *frontFixture) string {
			return filepath.Join(f.tracker_(), ".git", "info")
		}, ReasonNotClone},
		{"a tracker worktree outside .tracker", func(t *testing.T, f *frontFixture) string {
			out := filepath.Join(f.base, "outside")
			run(t, f.tracker_(), "worktree", "add", "-q", "--detach", out, "refs/remotes/origin/main")
			return out
		}, ReasonWorktree},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := newFrontFixture(t)
			from := c.break_(t, f)
			hb := hostTree(t, f.host)
			tr, err := Locate(from)
			if tr != nil || err == nil {
				t.Fatalf("want a refusal, got %v, %v", tr, err)
			}
			refusal(t, err, c.reason, "")
			sameTree(t, "the host", hb, hostTree(t, f.host))
		})
	}
	t.Run("a clone named .tracker in no host", func(t *testing.T) {
		f := newFrontFixture(t)
		lone := filepath.Join(realTemp(t), "x", ".tracker")
		run(t, f.base, "clone", "-q", f.tracker, lone)
		if tr, err := Locate(lone); tr != nil || err == nil {
			t.Errorf("want a refusal, got %v, %v", tr, err)
		}
	})
}

// G: the lock outlives the exec that replaces zn with the engine: its descriptor is not closed on exec.
func TestTheLockIsKeptAcrossExec(t *testing.T) {
	f := newFrontFixture(t)
	l, err := LockTracker(f.tracker_(), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Release()
	flags := func() uintptr {
		v, _, e := syscall.Syscall(syscall.SYS_FCNTL, l.f.Fd(), syscall.F_GETFD, 0)
		if e != 0 {
			t.Fatal(e)
		}
		return v
	}
	if flags()&syscall.FD_CLOEXEC == 0 {
		t.Fatal("the lock is already kept across exec before KeepAcrossExec: the test proves nothing")
	}
	l.KeepAcrossExec()
	if flags()&syscall.FD_CLOEXEC != 0 {
		t.Error("the lock's descriptor is closed on exec")
	}
}

// E, I: a refusal names every folder by its absolute path, and says what to do next.
func TestRefusalsUseAbsolutePathsAndSayWhatToDo(t *testing.T) {
	f := newFrontFixture(t)
	tr := f.located(t)
	steps, err := tr.Prepare(f.payload)
	if err != nil {
		t.Fatal(err)
	}
	for _, s := range steps {
		checkAbsolute(t, s)
	}
	os.WriteFile(filepath.Join(f.standing(), "mine.md"), []byte("x"), 0o644)
	run(t, f.standing(), "add", "mine.md")
	run(t, f.standing(), "commit", "-q", "-m", "mine")
	f.pushFrom(t, map[string]*string{"second.txt": str("2")}, nil)
	_, err = tr.Prepare(f.payload)
	refusal(t, err, ReasonWorktree, "git -C "+f.standing()+" push")
}

// every refuseTracker call in front.go passes a next step, so a refusal no test reaches still says what to do.
func TestEveryRefusalInTheSourceHasANextStep(t *testing.T) {
	src := readText(t, "front.go")
	calls := regexp.MustCompile(`refuseTracker\(`).FindAllStringIndex(src, -1)
	withNext := regexp.MustCompile(`refuseTracker\(Reason[A-Za-z]+, ("[^"]+"|next[A-Za-z]*|[a-z][A-Za-z]*Next),`).FindAllStringIndex(src, -1)
	if len(calls) < 15 {
		t.Fatalf("found only %d calls of refuseTracker", len(calls))
	}
	if len(calls) != len(withNext)+1 { // +1: the definition itself
		t.Errorf("%d calls of refuseTracker, %d with a next step", len(calls)-1, len(withNext))
	}
}

// relativeFolder is a folder of the tracker named from the host's top, which is wrong from any other folder.
var relativeFolder = regexp.MustCompile(`(^|[\s("'])((\.tracker|\.worktree|\.git)/[^\s(),;:"']*)`)

// checkAbsolute fails when a text names a folder of the tracker by a relative path.
func checkAbsolute(t *testing.T, text string) {
	t.Helper()
	for _, m := range relativeFolder.FindAllStringSubmatch(text, -1) {
		t.Errorf("a relative path %q in %q", m[2], text)
	}
}
