package host

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// pushFrom makes a commit in a fresh clone of the bare tracker with the given files (a nil body removes the path) and
// pushes it to main, as another machine would.
func (f *frontFixture) pushFrom(t *testing.T, files map[string]*string, links map[string]string) {
	t.Helper()
	other := filepath.Join(f.base, fmt.Sprintf("other%d", time.Now().UnixNano()))
	run(t, f.base, "clone", "-q", f.tracker, other)
	for p, body := range files {
		full := filepath.Join(other, p)
		if body == nil {
			run(t, other, "rm", "-q", "-r", "-f", p)
			continue
		}
		os.MkdirAll(filepath.Dir(full), 0o755)
		os.WriteFile(full, []byte(*body), 0o644)
	}
	for p, target := range links {
		os.MkdirAll(filepath.Dir(filepath.Join(other, p)), 0o755)
		os.Symlink(target, filepath.Join(other, p))
	}
	run(t, other, "add", "-A", "-f")
	run(t, other, "commit", "-q", "-m", "other")
	run(t, other, "push", "-q", "origin", "main")
}

func str(s string) *string { return &s }

func (f *frontFixture) located(t *testing.T) *Tracker {
	t.Helper()
	tr, err := Locate(f.host)
	if err != nil || tr == nil {
		t.Fatalf("%v %v", tr, err)
	}
	return tr
}

// B1, I: a tracker is data. A path zn owns in the worktree, at or under, refuses with its name; the way out the message
// gives (remove the path from the tracker's main) works.
func TestTheTrackerHoldsNoCode(t *testing.T) {
	for _, p := range []string{"z-nile/engine/x.luau", "z-nile/lib/x.sh", "z-nile/vendor/v.js", "z-nile/templates/t", "z-nile/roots.luau",
		"z-nile/affected.luau", "z-nile/bin/git", "z-nile/specs.luau", "z-nile/check.sh", "zn", ".luaurc", "AGENTS.md", "CLAUDE.md",
		".claude/settings.json", "z-nile/skills/a/SKILL.md"} {
		t.Run(p, func(t *testing.T) {
			f := newFrontFixture(t)
			tr := f.located(t)
			f.pushFrom(t, map[string]*string{p: str("x")}, nil)
			_, err := tr.Prepare(f.payload)
			refusal(t, err, ReasonCodeInTracker, p)
			if !strings.Contains(err.Error(), "a tracker is data") {
				t.Errorf("no reason in %q", err)
			}
			if _, e := os.Lstat(filepath.Join(f.standing(), "z-nile", "engine")); e == nil && strings.HasPrefix(p, "z-nile/engine") {
				t.Error("the engine link was made over the refusal")
			}
			f.pushFrom(t, map[string]*string{p: nil}, nil) // the way out
			if _, err := tr.Prepare(f.payload); err != nil {
				t.Errorf("after removing %s: %v", p, err)
			}
		})
	}
}

// B3, I: a tracked ignore file that un-hides a zn path refuses, naming it; removing the line works.
func TestATrackedNegationIsRefused(t *testing.T) {
	f := newFrontFixture(t)
	tr := f.located(t)
	f.pushFrom(t, map[string]*string{".gitignore": str(".cache/\nprompt.md\n.worktree/\n!/z-nile/engine\n")}, nil)
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonNotIgnored, "z-nile/engine")
	f.pushFrom(t, map[string]*string{".gitignore": str(".cache/\nprompt.md\n.worktree/\n")}, nil)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Errorf("after removing the negation: %v", err)
	}
	if st := run(t, f.standing(), "status", "--porcelain"); st != "" {
		t.Errorf("status %q", st)
	}
}

// C: a tracker whose z-nile is a link out of the tracker writes nothing into the host, in the two ways it can arrive.
func TestAZNileLinkCannotLeadTheLinksIntoTheHost(t *testing.T) {
	f := newFrontFixture(t)
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	before := hostTree(t, f.host)
	f.pushFrom(t, map[string]*string{"z-nile": nil}, map[string]string{"z-nile": "../../.."})
	if _, err := tr.Prepare(f.payload); err == nil {
		t.Error("a z-nile link was accepted")
	}
	sameTree(t, "the host", before, hostTree(t, f.host))
	// a worktree of the tracker of the caller's own, whose z-nile folder was swapped for a link to the host
	f2 := newFrontFixture(t)
	own := filepath.Join(f2.tracker_(), ".worktree", "mine")
	run(t, f2.tracker_(), "worktree", "add", "-q", "--detach", own, "refs/remotes/origin/main")
	os.RemoveAll(filepath.Join(own, "z-nile"))
	os.Symlink(f2.host, filepath.Join(own, "z-nile"))
	tr2, err := Locate(own)
	if err == nil && tr2 != nil {
		_, err = tr2.Prepare(f2.payload)
	}
	if err == nil || tr2 == nil && err == nil {
		t.Error("a swapped z-nile link was accepted")
	}
	for _, n := range []string{"engine", "roots.luau"} {
		if _, e := os.Lstat(filepath.Join(f2.host, n)); e == nil {
			t.Errorf("%s was written in the host", n)
		}
	}
	ents, _ := os.ReadDir(f2.host)
	for _, e := range ents {
		if strings.Contains(e.Name(), "zn-link") {
			t.Errorf("a temp link %s in the host", e.Name())
		}
	}
}

// F: the standing worktree never moves away from a commit that is not on origin/main, and an untracked file of someone
// else stops it too.
func TestStandingNeverDropsCommitsOrUntrackedFiles(t *testing.T) {
	f := newFrontFixture(t)
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(f.standing(), "mine.md"), []byte("x"), 0o644)
	run(t, f.standing(), "add", "mine.md")
	run(t, f.standing(), "commit", "-q", "-m", "my ticket")
	mine := run(t, f.standing(), "rev-parse", "HEAD")
	f.pushFrom(t, map[string]*string{"second.txt": str("2")}, nil)
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonWorktree, mine[:7])
	if !strings.Contains(err.Error(), "push") {
		t.Errorf("no way out in %q", err)
	}
	if got := run(t, f.standing(), "rev-parse", "HEAD"); got != mine {
		t.Errorf("HEAD moved to %s", got)
	}
}

// F: an untracked file of someone else in the standing worktree stops the refresh, naming it.
func TestStandingRefusesAnUntrackedFile(t *testing.T) {
	f := newFrontFixture(t)
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(f.standing(), "stray.txt"), []byte("x"), 0o644)
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonWorktree, "stray.txt")
	os.Remove(filepath.Join(f.standing(), "stray.txt")) // the way out
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Error(err)
	}
}

// J: a worktree registration left by a killed `worktree add` is repaired.
func TestAKilledWorktreeAddIsRepaired(t *testing.T) {
	f := newFrontFixture(t)
	tr := f.located(t)
	run(t, f.tracker_(), "worktree", "add", "-q", "--detach", f.standing(), "refs/remotes/origin/main")
	os.RemoveAll(f.standing())
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatalf("a registration without a folder: %v", err)
	}
	if run(t, f.standing(), "rev-parse", "HEAD") == "" {
		t.Error("no worktree")
	}
}

// J: a host zn cannot read (a separate git directory, the host's own git directory) refuses instead of falling back to
// the engine running in the host.
func TestLocateRefusesWhereItCannotReadTheHost(t *testing.T) {
	f := newFixture(t)
	sep := realTemp(t)
	host := filepath.Join(f.base, "host2")
	run(t, f.base, "init", "-q", "-b", "main", "--separate-git-dir="+filepath.Join(sep, "g"), host)
	os.MkdirAll(filepath.Join(host, ".tracker"), 0o755)
	if tr, err := Locate(host); tr != nil || err == nil {
		t.Errorf("a separate git dir: %v %v", tr, err)
	}
	g := newFrontFixture(t)
	if tr, err := Locate(filepath.Join(g.host, ".git", "hooks")); tr != nil || err == nil {
		t.Errorf("inside .git: %v %v", tr, err)
	}
}

// H: an address the git config rewrites for fetching or pushing is refused without showing it.
func TestARewrittenPushAddressIsRefused(t *testing.T) {
	other := ""
	for _, how := range []string{"pushurl", "global"} {
		t.Run(how, func(t *testing.T) {
			f := newFrontFixture(t)
			other = filepath.Join(f.base, "elsewhere-secret.git")
			os.MkdirAll(other, 0o755)
			run(t, other, "init", "-q", "--bare")
			if how == "pushurl" {
				run(t, f.tracker_(), "config", "remote.origin.pushurl", other)
			} else {
				cfg := readText(t, filepath.Join(f.home, ".gitconfig"))
				os.WriteFile(filepath.Join(f.home, ".gitconfig"), []byte(cfg+"[url \""+other+"\"]\n\tpushInsteadOf = "+f.tracker+"\n"), 0o644)
			}
			tr, err := Locate(f.host)
			if err == nil {
				_, err = tr.Prepare(f.payload)
			}
			refusal(t, err, ReasonAddress, "origin")
			if strings.Contains(err.Error(), "elsewhere-secret") {
				t.Errorf("the address is shown: %v", err)
			}
		})
	}
}

// G: the tracker's lock is exclusive, names its holder, and is given back.
func TestTheTrackerLock(t *testing.T) {
	f := newFrontFixture(t)
	a, err := LockTracker(f.tracker_(), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	_, err = LockTracker(f.tracker_(), 300*time.Millisecond)
	if err == nil || !strings.Contains(err.Error(), fmt.Sprint(os.Getpid())) {
		t.Errorf("a second lock: %v (want the holder's pid)", err)
	}
	a.Release()
	b, err := LockTracker(f.tracker_(), time.Second)
	if err != nil {
		t.Fatalf("after Release: %v", err)
	}
	b.Release()
}

// G: commands that wait for each other never collide: eight at once, one standing worktree, no error.
func TestConcurrentCommandsTakeTurns(t *testing.T) {
	f := newFrontFixture(t)
	var wg sync.WaitGroup
	errs := make(chan error, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			l, err := LockTracker(f.tracker_(), 60*time.Second)
			if err != nil {
				errs <- err
				return
			}
			defer l.Release()
			tr, err := Locate(f.host)
			if err == nil {
				_, err = tr.Prepare(f.payload)
			}
			errs <- err
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Error(err)
		}
	}
	// the link temp names never collide even without the lock
	var wg2 sync.WaitGroup
	target := filepath.Join(f.payload, "z-nile", "engine")
	path := filepath.Join(f.base, "lnk")
	for i := 0; i < 16; i++ {
		wg2.Add(1)
		go func() {
			defer wg2.Done()
			if _, err := ensureLink(path, target); err != nil && !errors.Is(err, os.ErrExist) {
				t.Error(err)
			}
		}()
	}
	wg2.Wait()
	if got, _ := os.Readlink(path); got != target {
		t.Errorf("link %q", got)
	}
}
