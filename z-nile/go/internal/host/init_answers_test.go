package host

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// plainGit runs git the way the user would, with their global config (the control for "the program would have run").
func (f *initFixture) plainGit(t *testing.T, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Env = append(os.Environ(), "HOME="+f.home, "GIT_CONFIG_NOSYSTEM=1")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

// evilFilter defines a smudge program in the user's global config and returns the marker it writes.
func (f *initFixture) evilFilter(t *testing.T) string {
	t.Helper()
	marker := filepath.Join(f.base, "marker")
	smudge := script(t, filepath.Join(f.base, "bin"), "smudge", marker, "cat")
	f.globalConfig(t, "[filter \"evil\"]\n\tsmudge = "+smudge+"\n\trequired = false\n")
	return marker
}

func (f *initFixture) noMarker(t *testing.T, marker string) {
	t.Helper()
	if b, err := os.ReadFile(marker); err == nil {
		t.Errorf("a program from the user's config ran:\n%s", b)
	}
}

// A: the checkout is of the commit that was scanned. A tag named main must not win, and no program defined in the
// user's config runs, whatever the tracker's attributes say.
func TestInitCheckoutIsOfTheScannedCommit(t *testing.T) {
	t.Run("a tag named main", func(t *testing.T) {
		f := newInitFixture(t)
		marker := f.evilFilter(t)
		f.seedTracker(t, "main", map[string]string{"z-nile/projects.toml": registryTOML})
		seed := filepath.Join(f.base, "tracker-seed")
		run(t, seed, "checkout", "-q", "-b", "other")
		os.WriteFile(filepath.Join(seed, ".gitattributes"), []byte("* filter=evil\n"), 0o644)
		run(t, seed, "add", "-A")
		run(t, seed, "commit", "-q", "-m", "evil")
		run(t, seed, "tag", "main")
		run(t, seed, "push", "-q", f.tracker, "refs/tags/main")
		run(t, f.tracker, "symbolic-ref", "HEAD", "refs/heads/trunk")
		mustInit(t, f.opts())
		f.noMarker(t, marker)
		tr := filepath.Join(f.host, ".tracker")
		if got := run(t, tr, "symbolic-ref", "HEAD"); got != "refs/heads/main" {
			t.Errorf("HEAD is %s: the checkout is not on the branch", got)
		}
		if _, err := os.Stat(filepath.Join(tr, ".gitattributes")); err == nil {
			t.Error("the tag's tree was checked out")
		}
		// control: an unprotected checkout of the same clone does run the program
		c := filepath.Join(f.base, "control")
		f.plainGit(t, "clone", "-q", "--no-checkout", f.tracker, c)
		f.plainGit(t, "-C", c, "checkout", "-q", "main")
		if _, err := os.Stat(marker); err != nil {
			t.Fatal("control: the unprotected checkout does not run the program, so the test proves nothing")
		}
	})
	t.Run("an attributes macro in the user's own file", func(t *testing.T) {
		f := newInitFixture(t)
		marker := f.evilFilter(t)
		attrs := filepath.Join(f.home, "attrs")
		os.WriteFile(attrs, []byte("[attr]evil filter=evil\n* evil\n"), 0o644)
		f.globalConfig(t, "[core]\n\tattributesFile = "+attrs+"\n")
		f.seedTracker(t, "main", map[string]string{"z-nile/projects.toml": registryTOML})
		mustInit(t, f.opts())
		f.noMarker(t, marker)
		if _, err := os.Stat(filepath.Join(f.host, ".tracker", "z-nile", "projects.toml")); err != nil {
			t.Error("main was not checked out")
		}
		c := filepath.Join(f.base, "control")
		f.plainGit(t, "clone", "-q", f.tracker, c)
		if _, err := os.Stat(marker); err != nil {
			t.Fatal("control: a plain clone does not run the program, so the test proves nothing")
		}
	})
}

// B: a run killed between the clone and the checkout leaves an empty working tree; the rerun checks out and says so.
func TestInitCompletesACheckoutThatWasCutShort(t *testing.T) {
	f := newInitFixture(t)
	f.seedTracker(t, "main", map[string]string{"z-nile/projects.toml": registryTOML, "README.md": "x\n"})
	tr := filepath.Join(f.host, ".tracker")
	run(t, f.base, "clone", "-q", "--no-checkout", f.tracker, tr)
	steps := mustInit(t, f.opts())
	if !strings.Contains(joined(steps), "checked out main") {
		t.Errorf("steps %q must say the checkout", steps)
	}
	if _, err := os.Stat(filepath.Join(tr, "README.md")); err != nil {
		t.Error("the working tree is still empty")
	}
	if st := run(t, tr, "status", "--porcelain"); st != "" {
		t.Errorf("status %q", st)
	}
	if steps := mustInit(t, f.opts()); len(steps) != 0 {
		t.Errorf("a third run took steps: %q", steps)
	}
}

// C: a skeleton file is never written through a link out of .tracker.
func TestInitWritesNothingThroughALinkedFolder(t *testing.T) {
	f := newInitFixture(t)
	tr := filepath.Join(f.host, ".tracker")
	run(t, f.base, "clone", "-q", f.tracker, tr)
	outside := filepath.Join(f.base, "outside")
	os.MkdirAll(outside, 0o755)
	if err := os.Symlink(outside, filepath.Join(tr, "z-nile")); err != nil {
		t.Fatal(err)
	}
	_, err := Init(f.opts())
	if err == nil || !strings.Contains(err.Error(), "z-nile") || !strings.Contains(err.Error(), "link") {
		t.Fatalf("want a refusal naming the link, got %v", err)
	}
	if ents, _ := os.ReadDir(outside); len(ents) != 0 {
		t.Errorf("something was written outside .tracker: %v", ents)
	}
}

// D: a hand-made local main with no registry is not pushed.
func TestInitDoesNotPushAMainWithNoRegistry(t *testing.T) {
	f := newInitFixture(t)
	tr := filepath.Join(f.host, ".tracker")
	run(t, f.base, "clone", "-q", f.tracker, tr)
	run(t, tr, "checkout", "-q", "-b", "main")
	commit(t, tr, "mine.txt")
	_, err := Init(f.opts())
	if err == nil || !strings.Contains(err.Error(), "z-nile/projects.toml") || !strings.Contains(err.Error(), "mine.txt") {
		t.Fatalf("want a refusal naming what main holds, got %v", err)
	}
	if run(t, f.tracker, "for-each-ref") != "" {
		t.Error("something was pushed")
	}
}

// E: init removes .tracker only when this run made it. A folder that appears after the checks is left alone.
func TestInitNeverRemovesAFolderItDidNotMake(t *testing.T) {
	f := newInitFixture(t)
	tr := filepath.Join(f.host, ".tracker")
	beforeClone = func() {
		os.MkdirAll(tr, 0o755)
		os.WriteFile(filepath.Join(tr, "unpushed-ticket"), []byte("mine\n"), 0o644)
	}
	defer func() { beforeClone = nil }()
	_, err := Init(f.opts())
	if err == nil || !strings.Contains(err.Error(), "appeared") {
		t.Fatalf("want a refusal saying .tracker appeared, got %v", err)
	}
	if readText(t, filepath.Join(tr, "unpushed-ticket")) != "mine\n" {
		t.Error("the other folder was changed")
	}
}

// E: a clone that fails removes the folder this run made, and nothing else.
func TestInitFailedCloneLeavesNoFolder(t *testing.T) {
	f := newInitFixture(t)
	o := f.opts()
	o.Tracker = filepath.Join(f.base, "does-not-exist.git")
	if _, err := Init(o); err == nil {
		t.Fatal("not refused")
	}
	if _, err := os.Lstat(filepath.Join(f.host, ".tracker")); err == nil {
		t.Error("a failed clone left .tracker behind")
	}
}

// F: every push address counts, not only the first.
func TestInitChecksEveryPushAddress(t *testing.T) {
	f := newInitFixture(t)
	other := filepath.Join(f.base, "elsewhere.git")
	os.MkdirAll(other, 0o755)
	run(t, other, "init", "-q", "--bare", "-b", "main")
	f.globalConfig(t, "[remote \"origin\"]\n\tpushurl = "+f.tracker+"\n\tpushurl = "+other+"\n")
	f.refuses(t, f.opts(), "push", "another repository")
	if run(t, other, "for-each-ref") != "" {
		t.Error("pushed to the second address")
	}
}
