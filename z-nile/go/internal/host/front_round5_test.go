package host

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// The fifth review round of f0428 step 4 (review-004.md): each test names the finding it guards.

// Q2: the search for a program attribute reads the original bytes; a byte before the line that a Unicode fold would
// lengthen or shorten (an invalid byte, Latin-1, a letter that grows, the Kelvin sign) never hides it.
func TestProgramAttributesAreFoundWhateverComesBefore(t *testing.T) {
	t.Parallel()
	for _, text := range []string{
		"#\xff\n* filter=x\n",
		"# caf\xe9 na\xefve r\xe9sum\xe9\n*.bin filter=lfs\n",
		"# Ⱥ\n* filter=x -text\n",
		"KKKK\n* filter=x\n",
		"#\xff\xfe\xfd\n*.md MERGE=evil\n",
		"ȺȺȺ\n*.md diff=evil\n",
	} {
		if attr, drv := programDriver(text); attr == "" || drv == "" {
			t.Errorf("not seen in %q", text)
		}
	}
}

// Q2: zn's verdict agrees with git's own: every file for which git check-attr reports a filter, merge or diff driver
// is refused by zn (zn may refuse more, never less).
func TestProgramAttributesAgreeWithGit(t *testing.T) {
	t.Parallel()
	repo := filepath.Join(realTemp(t), "r")
	run(t, filepath.Dir(repo), "init", "-q", "-b", "main", repo)
	for _, text := range []string{
		"* filter=x\n", "#\xff\n* filter=x\n", "# caf\xe9\n*.bin filter=lfs\n", "# Ⱥ\n* filter=x -text\n",
		"KKKK\n* filter=x\n", "\f#* filter=lfs\n", "\v#* merge=evil\n", " #* diff=evil\n",
		"\u0085#* filter=x\n", "[attr]m filter=x\n* m\n", "*.md text eol=lf -diff\n", "# a note\n* text\n", "* -filter\n",
		"* filter=\n", "* merge=\n", "* diff=\n", "*.bin filter= -text\n", // round 6 (T7): an empty driver name is a driver to git
	} {
		os.WriteFile(filepath.Join(repo, ".gitattributes"), []byte(text), 0o644)
		paths := []string{"a.bin", "x.md", "\f#x", "\v#x", " #x", "\u0085#x", "plain"}
		out := run(t, repo, append([]string{"check-attr", "filter", "merge", "diff", "--"}, paths...)...)
		gitSays := false
		for _, line := range strings.Split(out, "\n") {
			f := strings.Split(line, ": ")
			if len(f) >= 3 && f[2] != "unspecified" && f[2] != "set" && f[2] != "unset" {
				gitSays = true
			}
		}
		if attr, _ := programDriver(text); gitSays && attr == "" {
			t.Errorf("git sets a driver for %q and zn does not refuse it:\n%s", text, out)
		}
	}
}

// Q5: the PATH cleaner compares by identity: another case of the same folder, the data volume's alias of a folder, and
// an entry whose tail does not exist yet behind a linked prefix are all inside the root.
func TestThePathCleanerComparesByIdentity(t *testing.T) {
	t.Parallel()
	base := realTemp(t)
	root := filepath.Join(base, "Host")
	os.MkdirAll(filepath.Join(root, "bin"), 0o755)
	os.Symlink(root, filepath.Join(base, "linked"))
	cases := []string{
		filepath.Join(base, "linked", "not-yet", "bin"), // a tail that does not exist, behind a linked prefix
		filepath.Join(root, "bin"),
	}
	if _, err := os.Stat(filepath.Join(base, "HOST")); err == nil { // a case-insensitive disk
		cases = append(cases, filepath.Join(base, "HOST", "bin"))
	}
	if strings.HasPrefix(root, "/Users/") || strings.HasPrefix(root, "/private/") {
		if alias := filepath.Join("/System/Volumes/Data", root, "bin"); exists(alias) {
			cases = append(cases, alias)
		}
	}
	for _, e := range cases {
		if got := CleanPath(e+":/usr/bin", root); got != "/usr/bin" {
			t.Errorf("%s is inside %s but kept: %q", e, root, got)
		}
	}
	if got := CleanPath(filepath.Join(base, "Hostile", "bin")+":/usr/bin", root); !strings.HasPrefix(got, filepath.Join(base, "Hostile")) {
		t.Errorf("a sibling with a longer name was dropped: %q", got)
	}
}

// Q5: Locate's own git (readRepo) never takes an absolute PATH entry inside the repository, and when the only git is
// there it refuses, saying why, instead of running it.
func TestLocatesGitIsNeverInsideTheRepository(t *testing.T) {
	f := newFrontFixture(t)
	marker := filepath.Join(f.base, "ran")
	bin := filepath.Join(f.host, "src", "bin")
	os.MkdirAll(bin, 0o755)
	os.WriteFile(filepath.Join(bin, "git"), []byte("#!/bin/sh\n: > '"+marker+"'\nexec /usr/bin/git \"$@\"\n"), 0o755)
	t.Setenv("PATH", bin+":/usr/bin:/bin")
	if _, err := Locate(filepath.Join(f.host, "src")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err == nil {
		t.Error("a git inside the host ran")
	}
	t.Setenv("PATH", bin)
	_, err := Locate(filepath.Join(f.host, "src"))
	refusal(t, err, ReasonGit, "git")
	if _, err := os.Stat(marker); err == nil {
		t.Error("the only git, inside the host, ran")
	}
}

// Q7: a tracker repository zn opens also drops PATH entries inside its host, outside the tracker.
func TestATrackerOpenedDropsPathEntriesOfItsHost(t *testing.T) {
	f := newFrontFixture(t)
	bin := filepath.Join(f.host, "tools")
	os.MkdirAll(bin, 0o755)
	t.Setenv("PATH", bin+":/usr/bin:/bin")
	tr, err := openTracker(f.tracker_())
	if err != nil {
		t.Fatal(err)
	}
	for _, kv := range append(tr.reads, tr.writes...) {
		if strings.HasPrefix(kv, "PATH=") && strings.Contains(kv, bin) {
			t.Errorf("an entry of the host reached the tracker's git: %s", kv)
		}
	}
}

// Q7: a file origin/main in the standing worktree's own git directory is refused.
func TestAnOriginMainFileInTheWorktreesGitDirIsRefused(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(f.tracker_(), ".git", "worktrees", standingName, "origin", "main")
	os.MkdirAll(filepath.Dir(p), 0o755)
	os.WriteFile(p, []byte(run(t, f.tracker_(), "rev-parse", "HEAD")+"\n"), 0o644)
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonShortName, p)
}

// Q8: a clone made before zn cloned with --no-tags gets remote.origin.tagopt=--no-tags from Prepare; and the refusal
// of a ref that shadows origin/main says how to delete it here and that it may exist upstream.
func TestAnOldCloneStopsFetchingTags(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	run(t, f.tracker_(), "config", "--unset", "remote.origin.tagopt")
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	if got := run(t, f.tracker_(), "config", "remote.origin.tagopt"); got != "--no-tags" {
		t.Errorf("tagopt %q after Prepare", got)
	}
	run(t, f.tracker_(), "update-ref", "refs/tags/origin/main", run(t, f.tracker_(), "rev-parse", "HEAD"))
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonShortName, "refs/tags/origin/main")
	if !strings.Contains(err.Error(), "git tag -d origin/main") || !strings.Contains(err.Error(), "git push origin :refs/tags/origin/main") {
		t.Errorf("the next step does not name the local delete and the upstream one: %v", err)
	}
}

// Q7: a waiting zn names a stopped holder; the test waits until ps says the helper is stopped, never on a clock.
func waitStopped(t *testing.T, pid int) {
	t.Helper()
	for deadline := time.Now().Add(20 * time.Second); time.Now().Before(deadline); time.Sleep(20 * time.Millisecond) {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		out, err := exec.CommandContext(ctx, "/bin/ps", "-o", "stat=", "-p", strconv.Itoa(pid)).Output()
		cancel()
		if err == nil && strings.HasPrefix(strings.TrimSpace(string(out)), "T") {
			return
		}
	}
	t.Fatalf("pid %d never stopped", pid)
}
