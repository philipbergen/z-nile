package host

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// The third review round of f0428 step 4: each test names the finding it guards.

// N4(a): Locate judges what is on disk (HEAD, the files, the config, the layout), never origin/main as last fetched;
// Prepare judges origin/main after its fetch. So once a bad push is fixed upstream, a fresh Locate and Prepare work.
func TestTheWayOutWorksFromAFreshLocate(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	if _, err := f.located(t).Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	f.pushFrom(t, map[string]*string{"AGENTS.md": str("x")}, nil)
	tr := f.located(t) // a fresh Locate: the bad push is not on disk
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonCodeInTracker, "AGENTS.md")
	if _, err := Locate(f.host); err != nil {
		t.Fatalf("after the refusal, Locate refuses what Prepare fetched: %v", err)
	}
	f.pushFrom(t, map[string]*string{"AGENTS.md": nil}, nil) // the way out, upstream
	tr, err = Locate(f.host)
	if err != nil {
		t.Fatalf("a fresh Locate after the fix: %v", err)
	}
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Errorf("a fresh Prepare after the fix: %v", err)
	}
	// the same for a tracked negation
	f.pushFrom(t, map[string]*string{".gitignore": str(".cache/\nprompt.md\n.worktree/\n!/z-nile/engine\n")}, nil)
	if tr, err = Locate(f.host); err == nil {
		_, err = tr.Prepare(f.payload)
	}
	refusal(t, err, ReasonNotIgnored, "z-nile/engine")
	f.pushFrom(t, map[string]*string{".gitignore": str(".cache/\nprompt.md\n.worktree/\n")}, nil)
	if tr, err = Locate(f.host); err == nil {
		_, err = tr.Prepare(f.payload)
	}
	if err != nil {
		t.Errorf("after removing the negation: %v", err)
	}
}

// N4(a): what Locate no longer judges, Prepare does, from the main it fetched.
func TestPrepareJudgesTheFetchedMain(t *testing.T) {
	t.Parallel()
	t.Run("no registry", func(t *testing.T) {
		f := newFrontFixture(t)
		f.pushFrom(t, map[string]*string{registryPath: nil}, nil)
		tr := f.located(t)
		_, err := tr.Prepare(f.payload)
		refusal(t, err, ReasonNoRegistry, registryPath)
	})
	t.Run("no origin/main and no way to fetch it", func(t *testing.T) {
		f := newFrontFixture(t)
		run(t, f.tracker_(), "update-ref", "-d", "refs/remotes/origin/main")
		run(t, f.tracker_(), "config", "remote.origin.url", filepath.Join(f.base, "gone.git"))
		tr := f.located(t)
		_, err := tr.Prepare(f.payload)
		refusal(t, err, ReasonNotClone, "origin/main")
	})
}

// N4(b), (c): a refusal names a tracker path quoted for the shell, with control bytes and newlines escaped, and
// prints no command that names the wrong checkout.
func TestATrackerPathIsPrintedSafely(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	bad := "x\x1b[2J$(touch pwned)\nq/CLAUDE.md"
	f.pushFrom(t, map[string]*string{bad: str("x")}, nil)
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonCodeInTracker, "CLAUDE.md")
	msg := err.Error()
	if strings.ContainsAny(msg, "\x1b\n\r") {
		t.Errorf("raw control bytes in %q", msg)
	}
	if !strings.Contains(msg, `$'x\x1b[2J$(touch pwned)\nq/CLAUDE.md'`) {
		t.Errorf("the path is not quoted for the shell in %q", msg)
	}
	if strings.Contains(msg, "git -C") {
		t.Errorf("a command is printed: %q", msg)
	}
}

// N4(c): the quoting itself.
func TestShellQuote(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"up/.tracker/issues/f0001/f0001.md": "up/.tracker/issues/f0001/f0001.md",
		"a b":                               `'a b'`,
		"it's":                              `'it'\''s'`,
		"$(rm -rf ~)":                       `'$(rm -rf ~)'`,
		"x\ny":                              `$'x\ny'`,
		"\x1b[31m'":                         `$'\x1b[31m\''`,
		"back\\slash\x7f":                   `$'back\\slash\x7f'`,
		"\u009b31m":                         `$'\u009b31m'`,
		"":                                  `''`,
	} {
		if got := shellQuote(in); got != want {
			t.Errorf("shellQuote(%q) = %s, want %s", in, got, want)
		}
	}
}

// N3: attributes are judged in any case of their file name, and merge= and diff= are refused as filter= is: each names
// a program of the owner's config that git would run on the tracker's content.
func TestAttributesThatRunAProgramAreRefused(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	for _, c := range []struct{ path, text, want string }{
		{".GITATTRIBUTES", "* filter=lfs\n", "filter"},
		{"up/.GitAttributes", "* filter=evil\n", "filter"},
		{".gitattributes", "*.md merge=evil\n", "merge"},
		{".gitattributes", "*.md diff=evil\n", "diff"},
		{".gitattributes", "[attr]m filter=evil\n*.md m\n", "filter"},
	} {
		t.Run(c.path+" "+c.want, func(t *testing.T) {
			head := run(t, f.standing(), "rev-parse", "HEAD")
			f.pushFrom(t, map[string]*string{c.path: str(c.text)}, nil)
			_, err := tr.Prepare(f.payload)
			refusal(t, err, ReasonAttributes, c.want)
			if got := run(t, f.standing(), "rev-parse", "HEAD"); got != head {
				t.Errorf("the worktree moved to %s", got)
			}
			f.pushFrom(t, map[string]*string{c.path: nil}, nil)
			if _, err := tr.Prepare(f.payload); err != nil {
				t.Errorf("after removing it: %v", err)
			}
		})
	}
}

// N3: the standing worktree is made and moved with none of the user's own git config, so a filter the user's global
// attributes file selects never runs on the tracker's content.
func TestTheStandingCheckoutRunsNoUserFilter(t *testing.T) {
	f := newFrontFixture(t)
	f.ownHome(t)
	marker := filepath.Join(f.base, "smudged")
	attrs := filepath.Join(f.home, "attrs")
	os.WriteFile(attrs, []byte("* filter=evil\n"), 0o644)
	f.globalConfig(t, "[core]\n\tattributesFile = "+attrs+"\n[filter \"evil\"]\n\tsmudge = sh -c 'touch "+marker+"; cat'\n\tclean = cat\n")
	tr := f.located(t)
	if _, err := tr.Prepare(f.payload); err != nil { // makes the worktree
		t.Fatal(err)
	}
	f.pushFrom(t, map[string]*string{"second.txt": str("2")}, nil)
	if _, err := tr.Prepare(f.payload); err != nil { // moves it
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err == nil {
		t.Error("the user's filter ran on the tracker's content")
	}
}

// N6: a plain folder at the standing worktree's place is not taken for it, and the tracker's own checkout is left
// exactly as it was.
func TestAPlainFolderIsNotTheStandingWorktree(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	tr := f.located(t)
	os.MkdirAll(f.standing(), 0o755)
	head, branch := run(t, f.tracker_(), "rev-parse", "HEAD"), run(t, f.tracker_(), "symbolic-ref", "-q", "HEAD")
	f.pushFrom(t, map[string]*string{"second.txt": str("2")}, nil)
	before := tree(t, f.tracker_())
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonWorktree, f.standing())
	if got := run(t, f.tracker_(), "rev-parse", "HEAD"); got != head {
		t.Errorf("the tracker's own HEAD moved to %s", got)
	}
	if got := run(t, f.tracker_(), "symbolic-ref", "-q", "HEAD"); got != branch {
		t.Errorf("the tracker's own branch is now %q", got)
	}
	after := tree(t, f.tracker_())
	for k := range after {
		if strings.HasPrefix(k, ".git/") || k == ".git/" {
			delete(after, k)
		}
	}
	for k := range before {
		if strings.HasPrefix(k, ".git/") || k == ".git/" {
			delete(before, k)
		}
	}
	sameTree(t, "the tracker's own files", before, after)
}

// N7: the commit judged is the commit checked out: origin/main moving between the check and the checkout changes nothing.
func TestTheJudgedCommitIsTheOneCheckedOut(t *testing.T) {
	f := newFrontFixture(t)
	tr := f.located(t)
	other := filepath.Join(f.base, "racer")
	run(t, f.base, "clone", "-q", f.tracker, other)
	os.WriteFile(filepath.Join(other, "AGENTS.md"), []byte("x"), 0o644)
	run(t, other, "add", "AGENTS.md")
	run(t, other, "commit", "-q", "-m", "bad")
	bad := run(t, other, "rev-parse", "HEAD")
	run(t, other, "push", "-q", "origin", "HEAD:refs/heads/racer")
	run(t, f.tracker_(), "fetch", "-q", "origin", "racer")
	ran := false
	afterJudged = func() { // a concurrent fetch moves origin/main to a commit nobody judged
		ran = true
		run(t, f.tracker_(), "update-ref", "refs/remotes/origin/main", bad)
	}
	defer func() { afterJudged = nil }()
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	if !ran {
		t.Fatal("the seam between the check and the checkout was never reached")
	}
	if got := run(t, f.standing(), "rev-parse", "HEAD"); got == bad {
		t.Error("the commit nobody judged was checked out")
	}
	if _, err := os.Lstat(filepath.Join(f.standing(), "AGENTS.md")); err == nil {
		t.Error("AGENTS.md was checked out")
	}
}

// N8: when git cannot say which repository a folder is in (a damaged repository, no git), Locate refuses if a folder
// above holds a .tracker, instead of starting the engine in the host.
func TestLocateRefusesWhenGitCannotSay(t *testing.T) {
	t.Run("a damaged host repository", func(t *testing.T) {
		f := newFrontFixture(t)
		os.WriteFile(filepath.Join(f.host, ".git", "HEAD"), []byte("garbage\n"), 0o644)
		for _, from := range []string{f.host, filepath.Join(f.host, ".tracker", "upstream")} {
			tr, err := Locate(from)
			if tr != nil {
				t.Fatalf("located %v", tr)
			}
			if from == f.host {
				refusal(t, err, ReasonGit, f.host)
			} else if err == nil {
				t.Errorf("%s: no refusal", from)
			}
		}
	})
	t.Run("no git", func(t *testing.T) {
		f := newFrontFixture(t)
		t.Setenv("PATH", t.TempDir())
		tr, err := Locate(filepath.Join(f.host))
		if tr != nil {
			t.Fatalf("located %v", tr)
		}
		refusal(t, err, ReasonGit, f.host)
	})
	t.Run("outside every repository, with no .tracker above", func(t *testing.T) {
		if tr, err := Locate(t.TempDir()); tr != nil || err != nil {
			t.Errorf("%v %v", tr, err)
		}
	})
}

// N9: extensions.worktreeConfig is read as git reads a boolean, so "yes" turns the worktree's own config on and its
// keys are judged.
func TestAWorktreeConfigSwitchedOnByAnyBooleanIsJudged(t *testing.T) {
	t.Parallel()
	for _, v := range []string{"yes", "on", "1"} {
		t.Run(v, func(t *testing.T) {
			f := newFrontFixture(t)
			tr := f.located(t)
			run(t, f.tracker_(), "config", "extensions.worktreeConfig", v)
			if _, err := tr.Prepare(f.payload); err != nil {
				t.Fatal(err)
			}
			run(t, f.standing(), "config", "--worktree", "core.hooksPath", filepath.Join(f.standing(), "upstream"))
			if _, err := tr.Prepare(f.payload); err == nil || !strings.Contains(err.Error(), "core.hookspath") {
				t.Errorf("a hooksPath in the worktree's config with worktreeConfig=%s: %v", v, err)
			}
		})
	}
}

// N10(d): every error out of the front door is a refusal with a next step, and no reason code in its text, git's own
// failures and the host's refusals included.
func TestEveryErrorOfTheFrontDoorIsARefusal(t *testing.T) {
	t.Parallel()
	src := readText(t, "front.go")
	for _, fn := range []string{"func Locate(", "func (t *Tracker) Prepare(", "func (t *Tracker) Refresh(", "func LockTracker("} {
		at := strings.Index(src, fn)
		if at < 0 {
			t.Errorf("no %s", fn)
			continue
		}
		body := src[at:]
		if end := strings.Index(body, "\n}\n"); end > 0 {
			body = body[:end]
		}
		if !strings.Contains(body, "asRefusal(") {
			t.Errorf("%s returns errors that are not made refusals", fn)
		}
	}
	t.Run("git fails", func(t *testing.T) {
		f := newFrontFixture(t)
		idx := filepath.Join(f.tracker_(), ".git", "index")
		os.Chmod(idx, 0)
		defer os.Chmod(idx, 0o644)
		_, err := Locate(f.host)
		refusal(t, err, ReasonGit, "")
	})
	t.Run("a host with a separate git directory", func(t *testing.T) {
		f := newFixture(t)
		host := filepath.Join(f.base, "host2")
		run(t, f.base, "init", "-q", "-b", "main", "--separate-git-dir="+filepath.Join(realTemp(t), "g"), host)
		os.MkdirAll(filepath.Join(host, ".tracker"), 0o755)
		_, err := Locate(host)
		refusal(t, err, ReasonSeparateGitDir, host)
	})
	t.Run("the host's own refusal", func(t *testing.T) {
		f := newFrontFixture(t)
		p := filepath.Join(f.base, "blob")
		os.WriteFile(p, []byte("x"), 0o644)
		h := run(t, f.host, "hash-object", "-w", p)
		run(t, f.host, "update-index", "--add", "--cacheinfo", "100644,"+h+",.tracker/x")
		_, err := Locate(f.host)
		refusal(t, err, ReasonHost, ".tracker/x")
	})
	t.Run("the lock", func(t *testing.T) {
		f := newFrontFixture(t)
		os.Symlink(filepath.Join(f.base, "victim"), filepath.Join(f.tracker_(), ".git", "zn.lock"))
		_, err := LockTracker(f.tracker_(), 0)
		refusal(t, err, ReasonLock, "zn.lock")
	})
}

// N11: the names a program reads as code are refused nested anywhere (CLAUDE.md, AGENTS.md, .claude), and in any case
// fold or look-alike spelling a disk or a reader could take for them.
func TestLookAlikesAndNestedNamesAreRefused(t *testing.T) {
	t.Parallel()
	for _, p := range []string{
		"up/.tracker/issues/f0001/CLAUDE.md", "a/b/.claude/settings.json", "x/AGENTS.md", "up/agents.MD",
		"ＡGENTS.md",       // fullwidth A
		"АGENTS.md",       // Cyrillic A
		"zn​",             // a zero-width space
		"K/x",             // not owned: Kelvin sign alone (checked below as data)
		"CLAUDE.md́",      // a combining mark
		".claude/x",       // plain
		"ſ" + "cripts/x",  // long s folds to s
		"Z‐nile/engine/x", // a hyphen look-alike in z-nile
	} {
		if p == "K/x" {
			continue
		}
		if codeAt("100644", p) == "" {
			t.Errorf("%q is taken for data", p)
		}
	}
	for _, p := range []string{"日本/x.md", "notes/claude.txt", "up/.tracker/issues/f0001/f0001.md", "K/x", "agents/x.md", "znx", "claude-notes.md"} {
		if why := codeAt("100644", p); why != "" {
			t.Errorf("%q is refused: %s", p, why)
		}
	}
	// on disk too, at the top
	root := realTemp(t)
	os.MkdirAll(filepath.Join(root, "z-nile"), 0o755)
	os.WriteFile(filepath.Join(root, "ＡGENTS.md"), nil, 0o644)
	refusal(t, checkFiles(root, false), ReasonCodeInTracker, "GENTS.md")
}

var _ = regexp.MustCompile
