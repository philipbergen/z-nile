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
	os.MkdirAll(filepath.Dir(p), 0o755)
	b, _ := os.ReadFile(p)
	if err := os.WriteFile(p, append(b, []byte("\n"+strings.Join(lines, "\n")+"\n")...), 0o644); err != nil {
		t.Fatal(err)
	}
}

// refusedThenCleared pushes a change to the tracker's main as another machine would, sees Prepare refuse it naming
// want with the standing worktree left where it was and the host untouched, then pushes the way out (the change
// removed) and sees Prepare pass again.
func (f *frontFixture) refusedThenCleared(t *testing.T, tr *Tracker, files map[string]*string, links map[string]string, want string) {
	t.Helper()
	before, head := hostTree(t, f.host), run(t, f.standing(), "rev-parse", "HEAD")
	f.pushFrom(t, files, links)
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonCodeInTracker, want)
	if !strings.Contains(err.Error(), "a tracker is data") {
		t.Errorf("no reason in %q", err)
	}
	sameTree(t, "the host", before, hostTree(t, f.host))
	if got := run(t, f.standing(), "rev-parse", "HEAD"); got != head {
		t.Errorf("the standing worktree moved to the refused commit %s", got)
	}
	gone := map[string]*string{}
	for p := range files {
		gone[p] = nil
	}
	for p := range links {
		gone[p] = nil
	}
	f.pushFrom(t, gone, nil)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Errorf("after removing %s: %v", want, err)
	}
}

// B: a tracker's tree holds data only. A link or a submodule anywhere, anything under z-nile/ but the registry, the
// counter and the compaction map, and the paths that Lune, a model CLI or zn read as code (at or under, in any case)
// are refused, naming the path; removing it from the tracker's main is the way out.
func TestTheTrackerTreeIsDataOnly(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name  string
		files map[string]*string
		links map[string]string
		want  string
	}{
		{"a link to the host", nil, map[string]string{"upstream/.tracker/issues/f0001": "../../../.."}, "upstream/.tracker/issues/f0001"},
		{"a folder that wins over roots.luau", map[string]*string{"z-nile/roots/init.luau": str("x")}, nil, "z-nile/roots/init.luau"},
		{"a Lune script folder", map[string]*string{".lune/x.luau": str("x")}, nil, ".lune/x.luau"},
		{"another case of AGENTS.md", map[string]*string{"Agents.md": str("x")}, nil, "Agents.md"},
	}
	f := newFrontFixture(t) // one fixture: each case is pushed, refused, and taken out again
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f.refusedThenCleared(t, tr, c.files, c.links, c.want)
		})
	}
	// entries a case-insensitive disk could not make by hand: put straight into the index of another clone
	for _, c := range []struct{ name, mode, path string }{
		{"a submodule", "160000", "vendored"},
		{"another case of z-nile", "100644", "Z-Nile/engine/x.luau"},
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

// B: the rule for each tree entry, for every path the tests name (the end-to-end cases above and in
// TestTheTrackerHoldsNoCode prove that Prepare applies it to every entry of the commit it checks).
func TestEachTreeEntryIsDataOrRefused(t *testing.T) {
	t.Parallel()
	for _, p := range []string{"z-nile/engine/x.luau", "z-nile/lib/x.sh", "z-nile/vendor/v.js", "z-nile/templates/t", "z-nile/roots.luau",
		"z-nile/affected.luau", "z-nile/bin/git", "z-nile/specs.luau", "z-nile/check.sh", "zn", ".luaurc", "AGENTS.md", "CLAUDE.md",
		".claude/settings.json", "z-nile/skills/a/SKILL.md", "z-nile/roots/init.luau", "z-nile/affected", "z-nile/x.luau", "z-nile/.luaurc",
		"z-nile", ".lune/x.luau", "lune/x.luau", ".config.luau", ".models.toml", ".cache/x", ".worktree/x", "scripts/hooks/pre-bash.sh",
		"Agents.md", "Z-Nile/engine/x.luau", ".CLAUDE/settings.json", "ZN", "Z-NILE/projects.toml.bak"} {
		if codeAt("100644", p) == "" {
			t.Errorf("%s is taken for data", p)
		}
	}
	for _, p := range []string{"notes.md", "upstream/.tracker/issues/f0001"} {
		if codeAt("120000", p) == "" {
			t.Errorf("a link at %s is taken for data", p)
		}
	}
	if codeAt("160000", "vendored") == "" {
		t.Error("a submodule is taken for data")
	}
	for _, p := range []string{"z-nile/projects.toml", "z-nile/next", "z-nile/compaction.txt", "README.md", ".gitignore",
		"upstream/.tracker/issues/f0001/f0001.md", "upstream/.tracker/rafts/.gitkeep", "znotes.md", "lunetunes/x.md", "z-niles/x"} {
		if why := codeAt("100644", p); why != "" {
			t.Errorf("%s is refused: %s", p, why)
		}
	}
}

// B: on disk, the rule for each name in a checkout (the end-to-end cases in TestAnIgnoredFileAtAPathZnOwnsIsRefused
// prove that Locate and Prepare apply it to the tracker's checkout and the worktree).
func TestEachFileOnDiskIsDataOrRefused(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		work  bool
		make  func(root string)
		named string
	}{
		{false, func(r string) { os.WriteFile(filepath.Join(r, "AGENTS.md"), nil, 0o644) }, "AGENTS.md"},
		{true, func(r string) { os.WriteFile(filepath.Join(r, "agents.md"), nil, 0o644) }, "agents.md"},
		{true, func(r string) { os.MkdirAll(filepath.Join(r, ".claude"), 0o755) }, ".claude"},
		{true, func(r string) { os.WriteFile(filepath.Join(r, ".luaurc"), nil, 0o644) }, ".luaurc"},
		{true, func(r string) { os.WriteFile(filepath.Join(r, "zn"), nil, 0o755) }, "zn"},
		{true, func(r string) { os.RemoveAll(filepath.Join(r, ".cache")); os.Symlink(r, filepath.Join(r, ".cache")) }, ".cache"},
		{false, func(r string) {
			os.RemoveAll(filepath.Join(r, ".worktree"))
			os.WriteFile(filepath.Join(r, ".worktree"), nil, 0o644)
		}, ".worktree"},
		{true, func(r string) { os.WriteFile(filepath.Join(r, "z-nile", ".luaurc"), nil, 0o644) }, "z-nile/.luaurc"},
		{true, func(r string) { os.MkdirAll(filepath.Join(r, "z-nile", "bin"), 0o755) }, "z-nile/bin"},
		{true, func(r string) { os.WriteFile(filepath.Join(r, "z-nile", "engine"), nil, 0o644) }, "z-nile/engine"},
		{false, func(r string) { os.Symlink(r, filepath.Join(r, "z-nile", "engine")) }, "z-nile/engine"},
		{true, func(r string) {
			os.Remove(filepath.Join(r, "z-nile", "projects.toml"))
			os.Symlink(r, filepath.Join(r, "z-nile", "projects.toml"))
		}, "z-nile/projects.toml"},
		{true, func(r string) { os.RemoveAll(filepath.Join(r, "z-nile")); os.Symlink(r, filepath.Join(r, "z-nile")) }, "z-nile"},
	} {
		root := realTemp(t)
		os.MkdirAll(filepath.Join(root, "z-nile"), 0o755)
		os.WriteFile(filepath.Join(root, "z-nile", "projects.toml"), nil, 0o644)
		os.WriteFile(filepath.Join(root, "z-nile", "next"), nil, 0o644)
		os.MkdirAll(filepath.Join(root, ".cache", "nohooks"), 0o755)
		os.MkdirAll(filepath.Join(root, ".worktree", "zn"), 0o755)
		os.MkdirAll(filepath.Join(root, "upstream", ".tracker"), 0o755)
		if err := checkFiles(root, c.work); err != nil {
			t.Fatalf("a clean checkout: %v", err)
		}
		if c.work {
			os.Symlink(root, filepath.Join(root, "z-nile", "lib")) // a link of zn's is fine in the worktree
		}
		c.make(root)
		refusal(t, checkFiles(root, c.work), ReasonCodeInTracker, filepath.Join(root, c.named))
	}
}

// B: the tracker's main checkout is judged by what it holds, not only by origin/main: a local commit there that adds
// code is refused before anything runs.
func TestTheTrackersOwnCheckoutHoldsNoCode(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	os.WriteFile(filepath.Join(f.tracker_(), "zn"), []byte("#!/bin/sh\n"), 0o755)
	run(t, f.tracker_(), "add", "zn")
	run(t, f.tracker_(), "commit", "-q", "-m", "a wrapper")
	tr, err := Locate(f.host)
	if tr != nil {
		t.Fatalf("located %v", tr)
	}
	refusal(t, err, ReasonCodeInTracker, "zn")
	// a link that names nothing zn owns is seen only in the commit
	g := newFrontFixture(t)
	os.Symlink("../..", filepath.Join(g.tracker_(), "notes.md"))
	run(t, g.tracker_(), "add", "notes.md")
	run(t, g.tracker_(), "commit", "-q", "-m", "a link")
	tr, err = Locate(g.host)
	if tr != nil {
		t.Fatalf("located %v", tr)
	}
	refusal(t, err, ReasonCodeInTracker, "notes.md")
}

// B: a file at a path zn owns is refused even when git cannot see it (ignored), in the tracker's checkout and in the
// worktree the engine runs in.
func TestAnIgnoredFileAtAPathZnOwnsIsRefused(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t) // one fixture: each file is made, refused, and removed again
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct{ where, path, named string }{
		{"tracker", ".claude/settings.json", ".claude"}, {"standing", "z-nile/.luaurc", "z-nile/.luaurc"}, {"standing", "zn", "zn"},
	} {
		t.Run(c.where+" "+c.path, func(t *testing.T) {
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
			os.RemoveAll(filepath.Join(root, c.named)) // the way out
			if tr2, err = Locate(f.host); err == nil {
				_, err = tr2.Prepare(f.payload)
			}
			if err != nil {
				t.Errorf("after removing it: %v", err)
			}
		})
	}
}

// C: no folder zn writes through is a link: the worktree folder, the standing worktree's cache folder, the tracker's
// info folder and its lock. Each is refused and nothing is written where the link points.
func TestNoComponentZnWritesThroughIsALink(t *testing.T) {
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
			return filepath.Join(f.tracker_(), ".git", "refs")
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
	src := readText(t, "front.go")
	calls := regexp.MustCompile(`refuseTracker\(`).FindAllStringIndex(src, -1)
	withNext := regexp.MustCompile(`refuseTracker\([A-Za-z]+, ("[^"]+"|next),`).FindAllStringIndex(src, -1)
	if len(calls) < 15 {
		t.Fatalf("found only %d calls of refuseTracker", len(calls))
	}
	if len(calls) != len(withNext)+1 { // +1: the definition itself
		t.Errorf("%d calls of refuseTracker, %d with a next step", len(calls)-1, len(withNext))
	}
}

// relativeFolder is a folder of the tracker named from the host's top, which is wrong from any other folder.
var relativeFolder = regexp.MustCompile(`(^|[\s("'])((\.tracker|\.worktree|\.git)/[^\s(),;:"']*)`)

// quoted is a span in backticks: a path inside a commit, or a command with one, which is repository-relative.
var quoted = regexp.MustCompile("`[^`]*`")

// checkAbsolute fails when a text names a folder of the tracker by a relative path outside a quoted span.
func checkAbsolute(t *testing.T, text string) {
	t.Helper()
	for _, m := range relativeFolder.FindAllStringSubmatch(quoted.ReplaceAllString(text, ""), -1) {
		t.Errorf("a relative path %q in %q", m[2], text)
	}
}
