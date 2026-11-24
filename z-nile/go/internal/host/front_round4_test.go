package host

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// The fourth review round of f0428 step 4 (review-003.md): each test names the finding it guards.

// P1: the PATH zn's own git runs with keeps absolute entries only, and none inside a folder someone else may write.
func TestZnsOwnGitGetsAnAbsolutePathOnly(t *testing.T) {
	t.Parallel()
	in := []string{"PATH=./bin:bin::/usr/bin:/r/host/.tracker/bin:/r/hostbin:/bin", "HOME=/h"}
	for name, env := range map[string][]string{"reads": readEnv(in, ""), "writes": writeEnv(in, "")} {
		for _, kv := range env {
			if v, ok := strings.CutPrefix(kv, "PATH="); ok && v != "/usr/bin:/r/host/.tracker/bin:/r/hostbin:/bin" {
				t.Errorf("%s: PATH=%s", name, v)
			}
		}
	}
	if got := CleanPath("./bin:bin::/usr/bin:/r/host/.tracker/bin:/r/hostbin:/r/host:/bin", "/r/host"); got != "/usr/bin:/r/hostbin:/bin" {
		t.Errorf("CleanPath kept %q", got)
	}
	// a repository opened by zn never gets a PATH entry inside it
	f := newFixture(t)
	r := f.open()
	for _, env := range [][]string{withoutRootPath([]string{"PATH=/usr/bin:" + filepath.Join(f.host, "bin") + ":/bin"}, r.root)} {
		for _, kv := range env {
			if strings.HasPrefix(kv, "PATH=") && strings.Contains(kv, f.host) {
				t.Errorf("an entry inside the repository: %s", kv)
			}
		}
	}
}

// P2: a ref other than refs/remotes/origin/main that git's short name origin/main could resolve to (a tag, a branch,
// refs/origin/main, refs/remotes/origin/main/HEAD, a file in the git directory) is refused, naming it and saying how to
// remove it; removing it is the way out.
func TestAnotherRefNamedOriginMainIsRefused(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	other := filepath.Join(f.base, "shadow")
	run(t, f.base, "clone", "-q", f.tracker, other)
	commit(t, other, "shadow.txt")
	run(t, other, "push", "-q", "origin", "HEAD:refs/heads/shadow")
	run(t, f.tracker_(), "fetch", "-q", "origin", "refs/heads/shadow:refs/zn-test/shadow")
	sha := run(t, f.tracker_(), "rev-parse", "refs/zn-test/shadow")
	for _, ref := range []string{"refs/tags/origin/main", "refs/heads/origin/main", "refs/origin/main"} {
		t.Run(ref, func(t *testing.T) {
			run(t, f.tracker_(), "update-ref", ref, sha)
			_, err := tr.Prepare(f.payload)
			refusal(t, err, ReasonShortName, ref)
			run(t, f.tracker_(), "update-ref", "-d", ref)
			if _, err := tr.Prepare(f.payload); err != nil {
				t.Errorf("after removing %s: %v", ref, err)
			}
		})
	}
	t.Run("a file in the git directory", func(t *testing.T) {
		p := filepath.Join(f.tracker_(), ".git", "origin", "main")
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte(sha+"\n"), 0o644)
		_, err := tr.Prepare(f.payload)
		refusal(t, err, ReasonShortName, p)
		os.RemoveAll(filepath.Dir(p))
		if _, err := tr.Prepare(f.payload); err != nil {
			t.Errorf("after removing it: %v", err)
		}
	})
}

// P2: the tracker is cloned with no tags, so a tag a pusher named origin/main never reaches a new clone.
func TestTheTrackerIsClonedWithNoTags(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	other := filepath.Join(f.base, "tagger")
	run(t, f.base, "clone", "-q", f.tracker, other)
	run(t, other, "tag", "origin/main")
	run(t, other, "tag", "v1")
	run(t, other, "push", "-q", "origin", "--tags")
	dest := filepath.Join(f.host, ".cache", "second-clone")
	if err := cloneTracker(f.open(), f.tracker, dest); err != nil {
		t.Fatal(err)
	}
	if tags := run(t, dest, "tag", "-l"); tags != "" {
		t.Errorf("the clone took tags: %q", tags)
	}
}

// P5: a filter=, merge= or diff= token anywhere in an attributes file is refused, a line that is a comment to a reader
// trimming more than git does (form feed, vertical tab, NBSP, NEL before #) and a plain comment included.
func TestAProgramAttributeIsRefusedEvenInAComment(t *testing.T) {
	t.Parallel()
	for _, lead := range []string{"\f", "\v", " ", "\u0085", "", " "} {
		for _, attr := range []string{"filter=lfs", "merge=evil", "diff=evil"} {
			text := "*.md text\n" + lead + "#* " + attr + "\n"
			if a, drv := programDriver(text); a == "" || drv == "" {
				t.Errorf("%q is not seen in %q", attr, text)
			}
		}
	}
	if a, drv := programDriver("*.md text eol=lf -diff\n# a note\n"); a != "" || drv != "" {
		t.Errorf("a plain file is refused: %s=%s", a, drv)
	}
	// and end to end, through the tracker
	f := newFrontFixture(t)
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	f.pushFrom(t, map[string]*string{".gitattributes": str("\f#* filter=lfs\n")}, nil)
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonAttributes, "filter")
}

// P6: a top-level name of the tracker that is not plain printable ASCII is refused (APFS opens .conﬁg.luau, with a
// ligature, as .config.luau), in the tree and on disk; below the top any name is data.
func TestATopLevelNameIsPlainASCII(t *testing.T) {
	t.Parallel()
	for _, p := range []string{".conﬁg.luau", "日本/x.md", "K/x", "café.md", "tab\tname", "a\x7fb"} {
		if codeAt("100644", p) == "" {
			t.Errorf("%q is taken for data", p)
		}
	}
	for _, p := range []string{"README.md", ".gitignore", "up/.tracker/issues/f0001/café.md", "a b.md"} {
		if why := codeAt("100644", p); why != "" {
			t.Errorf("%q is refused: %s", p, why)
		}
	}
	root := realTemp(t)
	os.MkdirAll(filepath.Join(root, "z-nile"), 0o755)
	os.WriteFile(filepath.Join(root, ".conﬁg.luau"), nil, 0o644)
	refusal(t, checkFiles(root, false), ReasonCodeInTracker, "g.luau")
}

// P7: bidi and invisible line characters are escaped for the terminal and for the shell; an emoji joiner is not.
func TestBidiAndInvisibleCharactersAreEscaped(t *testing.T) {
	t.Parallel()
	for _, r := range []rune{0x202a, 0x202b, 0x202c, 0x202d, 0x202e, 0x2066, 0x2067, 0x2068, 0x2069, 0x200e, 0x200f, 0x061c, 0x2028, 0x2029} {
		s := "a" + string(r) + "b"
		if got := terminalSafe(s); strings.ContainsRune(got, r) || !strings.Contains(got, `\u`) {
			t.Errorf("terminalSafe(%U) = %q", r, got)
		}
		if got := shellQuote(s); strings.ContainsRune(got, r) || !strings.HasPrefix(got, "$'") {
			t.Errorf("shellQuote(%U) = %q", r, got)
		}
	}
	joined := "\U0001F468‍\U0001F469"
	if got := terminalSafe(joined); got != joined {
		t.Errorf("an emoji joiner was escaped: %q", got)
	}
}

// P9: zn remembers where it put the standing worktree (refs/zn/standing), so after main is rewound upstream the
// worktree moves on; a commit the owner made on top is still never left behind.
func TestARewoundMainMovesTheWorktree(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	before := run(t, f.tracker, "rev-parse", "main")
	f.pushFrom(t, map[string]*string{"spam.txt": str("spam")}, nil)
	if _, err := tr.Prepare(f.payload); err != nil { // the worktree moves to the spam commit
		t.Fatal(err)
	}
	run(t, f.tracker, "update-ref", "refs/heads/main", before) // the owner rewinds main upstream
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatalf("after the rewind: %v", err)
	}
	if got := run(t, f.standing(), "rev-parse", "HEAD"); got != before {
		t.Errorf("the worktree is at %s, want the rewound main %s", got, before)
	}
	// a commit of the owner's on top is still protected
	os.WriteFile(filepath.Join(f.standing(), "mine.md"), []byte("x"), 0o644)
	run(t, f.standing(), "add", "mine.md")
	run(t, f.standing(), "commit", "-q", "-m", "mine")
	mine := run(t, f.standing(), "rev-parse", "HEAD")
	f.pushFrom(t, map[string]*string{"later.txt": str("2")}, nil)
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonWorktree, mine[:7])
}

// P3: a zn that waits for the lock says when the zn that holds it is stopped (Ctrl-Z), and how to go on.
func TestAWaitingZnSaysTheHolderIsStopped(t *testing.T) {
	f := newFrontFixture(t)
	ready := filepath.Join(f.base, "locked")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	helper := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestLockHolderHelper$")
	helper.Env = append(os.Environ(), "HOST_LOCK_HELPER="+f.tracker_(), "HOST_LOCK_READY="+ready)
	if err := helper.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { helper.Process.Kill(); helper.Wait() }()
	for i := 0; i < 600 && !exists(ready); i++ {
		time.Sleep(50 * time.Millisecond)
	}
	if !exists(ready) {
		t.Fatal("the helper never took the lock")
	}
	syscall.Kill(helper.Process.Pid, syscall.SIGSTOP)
	defer syscall.Kill(helper.Process.Pid, syscall.SIGCONT)
	_, err := LockTracker(f.tracker_(), 200*time.Millisecond)
	refusal(t, err, ReasonLock, "is stopped")
}

// TestLockHolderHelper is the zn TestAWaitingZnSaysTheHolderIsStopped stops: it runs only with its variables set.
func TestLockHolderHelper(t *testing.T) {
	dir := os.Getenv("HOST_LOCK_HELPER")
	if dir == "" {
		t.Skip("run by TestAWaitingZnSaysTheHolderIsStopped")
	}
	l, err := LockTracker(dir, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer l.Release()
	os.WriteFile(os.Getenv("HOST_LOCK_READY"), nil, 0o644)
	time.Sleep(25 * time.Second)
}
