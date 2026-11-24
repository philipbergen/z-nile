package host

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"znile/internal/fxtree"
)

// frontFixture is a host with `zn init` done, so its tracker is a clone of a bare tracker, plus a stand-in for the
// extracted payload (the folder the engine's files are linked from).
type frontFixture struct {
	*initFixture
	payload string
}

// frontTemplate is one frontFixture built once per test binary and kept outside every test's temp folder, so each
// test copies it (a few hundred small files) instead of running the forty-odd git commands of a fresh host, init and
// payload. base and payload are where the template was built: the copies' git config files name base, and are
// rewritten to the copy's.
var frontTemplate struct {
	once          sync.Once
	dir           string // holds base/ and payload/
	base, payload string // where the template was built
	err           error
}

// copyTree copies src to dst (which must not exist): a copy-on-write clone where the volume can (fxtree), else cp -Rp.
func copyTree(src, dst string) error { return fxtree.Copy(src, dst) }

// buildFrontFixture is a host after zn init and a stand-in payload, under the fixtures' process-wide HOME (TestMain),
// so it sets no variable and may run in a parallel test.
func buildFrontFixture(t *testing.T) *frontFixture {
	t.Helper()
	f := &frontFixture{initFixture: newInitFixture(t)}
	mustInit(t, f.opts())
	pack(t, f.upstream, f.fork, f.tracker, f.seed, f.host, f.tracker_())
	// the seed only made the upstream's history; no front-door test touches it, so its repository is not in the template
	// (it was a quarter of every copy's entries, made and removed by each of a hundred tests: c0179)
	if err := os.RemoveAll(f.seed); err != nil {
		t.Fatal(err)
	}
	f.payload = realTemp(t)
	for _, d := range []string{"engine", "lib", "vendor", "templates"} {
		os.MkdirAll(filepath.Join(f.payload, "z-nile", d), 0o755)
		os.WriteFile(filepath.Join(f.payload, "z-nile", d, "x"), []byte(d), 0o644)
	}
	for _, n := range []string{"roots.luau", "affected.luau"} {
		os.WriteFile(filepath.Join(f.payload, "z-nile", n), []byte(n), 0o644)
	}
	return f
}

func newFrontFixture(t *testing.T) *frontFixture {
	t.Helper()
	tp := &frontTemplate
	tp.once.Do(func() {
		f := buildFrontFixture(t)
		tp.base, tp.payload = f.base, f.payload
		if tp.dir, tp.err = os.MkdirTemp("", "zn-front-template-"); tp.err != nil {
			return
		}
		for _, c := range [][2]string{{f.base, "base"}, {f.payload, "payload"}} {
			if tp.err = copyTree(c[0], filepath.Join(tp.dir, c[1])); tp.err != nil {
				return
			}
		}
	})
	if tp.err != nil || tp.dir == "" {
		t.Fatalf("the fixture template could not be built (%v): see the first test that built it", tp.err)
	}
	root := realTemp(t)
	base, payload := filepath.Join(root, "base"), filepath.Join(root, "payload")
	for _, c := range [][2]string{{"base", base}, {"payload", payload}} {
		if err := copyTree(filepath.Join(tp.dir, c[0]), c[1]); err != nil {
			t.Fatal(err)
		}
	}
	// the git config files name the remotes by absolute path: point them at the copy
	rebase(t, base, tp.base, []string{"host/.tracker/.git/config", "host/.git/config"}) // not seed/.git/config: no seed in the template
	return &frontFixture{initFixture: &initFixture{
		fixture: &fixture{t: t, base: base, upstream: filepath.Join(base, "upstream.git"), fork: filepath.Join(base, "fork.git"),
			host: filepath.Join(base, "host"), seed: filepath.Join(base, "seed")},
		tracker: filepath.Join(base, "tracker.git"), home: os.Getenv("HOME"),
	}, payload: payload}
}

// realHome is the HOME the test binary started with (rokit's tool storage is found there); fixtureHome replaces it for
// every test, so no test reads the user's own git config, and the front-door tests can run in parallel without setting
// a variable.
var realHome = os.Getenv("HOME")

// TestMain sets the fixtures' HOME (a git identity, nothing else) and removes it and the fixture templates at the end.
func TestMain(m *testing.M) {
	home, err := os.MkdirTemp("", "zn-host-home-")
	if err == nil {
		home, err = filepath.EvalSymlinks(home)
	}
	if err == nil {
		fixtureGitTemplate = filepath.Join(home, "gittemplate")
		err = makeGitTemplate(fixtureGitTemplate)
	}
	if err == nil { // transfer.unpackLimit: a push or fetch keeps one pack, not a file per object (c0179)
		err = os.WriteFile(filepath.Join(home, ".gitconfig"), []byte("[user]\n\tname = Test User\n\temail = 1+test@users.noreply.github.com\n[init]\n\ttemplateDir = "+fixtureGitTemplate+"\n[transfer]\n\tunpackLimit = 1\n"), 0o644)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	os.Setenv("HOME", home)
	os.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	code := m.Run()
	os.RemoveAll(home)
	for _, d := range []string{frontTemplate.dir, fixtureTemplate.dir} {
		if d != "" {
			os.RemoveAll(d)
		}
	}
	os.Exit(code)
}

func (f *frontFixture) tracker_() string { return filepath.Join(f.host, ".tracker") }
func (f *frontFixture) standing() string { return filepath.Join(f.host, ".tracker", ".worktree", "zn") }

// hostTree is every file of the host outside .tracker, its .git folder included.
func hostTree(t *testing.T, host string) map[string]string {
	t.Helper()
	all := tree(t, host)
	for k := range all {
		if k == ".tracker/" || strings.HasPrefix(k, ".tracker/") {
			delete(all, k)
		}
	}
	return all
}

func refusal(t *testing.T, err error, want TrackerReason, mention string) {
	t.Helper()
	var r *TrackerRefusal
	if !errors.As(err, &r) {
		t.Fatalf("want a TrackerRefusal %s, got %v", want, err)
	}
	if r.Reason != want {
		t.Errorf("reason %q, want %q (%v)", r.Reason, want, err)
	}
	if !strings.Contains(err.Error(), mention) {
		t.Errorf("the message %q does not name %q", err, mention)
	}
	// I: every refusal says what to do next, as its last sentence; E: it names folders by absolute paths
	if strings.TrimSpace(r.Next) == "" || !strings.HasSuffix(err.Error(), r.Next) {
		t.Errorf("the refusal %q says nothing to do next (%q)", err, r.Next)
	}
	checkAbsolute(t, err.Error())
	// N10(d): the reason is the field's, never a code word in the text the owner reads
	if strings.Contains(err.Error(), string(r.Reason)) {
		t.Errorf("the reason code %q is in the text %q", r.Reason, err)
	}
}

// A: a repository with no .tracker clone at its top has no tracker, whatever else it holds: the engine runs as before.
func TestLocateFindsNoTrackerWhereThereIsNone(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	if tr, err := Locate(f.host); tr != nil || err != nil {
		t.Fatalf("a plain host: %v, %v", tr, err)
	}
	// a repository like pickman: its tickets live inside it, under <project>/.tracker, never at its top
	os.MkdirAll(filepath.Join(f.host, "z-nile", ".tracker", "issues"), 0o755)
	os.MkdirAll(filepath.Join(f.host, "z-nile", "engine"), 0o755)
	os.WriteFile(filepath.Join(f.host, "z-nile", "projects.toml"), []byte("x"), 0o644)
	for _, dir := range []string{f.host, filepath.Join(f.host, "z-nile"), filepath.Join(f.host, "z-nile", ".tracker", "issues")} {
		if tr, err := Locate(dir); tr != nil || err != nil {
			t.Errorf("%s: %v, %v", dir, tr, err)
		}
	}
	if tr, err := Locate(t.TempDir()); tr != nil || err != nil {
		t.Errorf("a folder outside every repository: %v, %v", tr, err)
	}
	// a linked worktree of such a repository is the same
	wt := filepath.Join(f.base, "wt")
	run(t, f.host, "worktree", "add", "-q", "--detach", wt)
	if tr, err := Locate(wt); tr != nil || err != nil {
		t.Errorf("a linked worktree of a repository with no tracker: %v, %v", tr, err)
	}
}

// A (AC3): every folder of the host, of a linked host worktree, of the tracker and of a tracker worktree resolves the
// one tracker, and the engine runs in the standing worktree unless the caller is in a tracker worktree of its own.
func TestLocateResolvesTheOneTrackerFromEveryFolder(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	os.MkdirAll(filepath.Join(f.host, "src", "deep"), 0o755)
	hostWt := filepath.Join(f.base, "hostwt")
	run(t, f.host, "worktree", "add", "-q", "--detach", hostWt)
	os.MkdirAll(filepath.Join(hostWt, "sub"), 0o755)
	own := filepath.Join(f.tracker_(), ".worktree", "mine")
	run(t, f.tracker_(), "worktree", "add", "-q", "--detach", own, "refs/remotes/origin/main")
	os.MkdirAll(filepath.Join(own, "upstream"), 0o755)
	stand := f.standing()
	cases := []struct{ from, work string }{
		{f.host, stand}, {filepath.Join(f.host, "src", "deep"), stand}, {hostWt, stand}, {filepath.Join(hostWt, "sub"), stand},
		{f.tracker_(), stand}, {filepath.Join(f.tracker_(), "upstream"), stand},
		{own, own}, {filepath.Join(own, "upstream"), own},
	}
	for _, c := range cases {
		tr, err := Locate(c.from)
		if err != nil || tr == nil {
			t.Fatalf("%s: %v, %v", c.from, tr, err)
		}
		if tr.Host != f.host || tr.Dir != f.tracker_() || tr.Work != c.work {
			t.Errorf("%s: host %s, tracker %s, work %s; want %s, %s, %s", c.from, tr.Host, tr.Dir, tr.Work, f.host, f.tracker_(), c.work)
		}
	}
}

// A: Locate only reads: the host and the tracker are byte for byte what they were.
func TestLocateWritesNothing(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	hb, tb := hostTree(t, f.host), tree(t, f.tracker_())
	if tr, err := Locate(f.host); err != nil || tr == nil {
		t.Fatalf("%v %v", tr, err)
	}
	sameTree(t, "the host", hb, hostTree(t, f.host))
	sameTree(t, "the tracker", tb, tree(t, f.tracker_()))
}

// C: a tracker that cannot be used is refused naming the cause, and nothing changes in the host or the tracker. (Round 3,
// N4(a): a missing registry and a missing origin/main are Prepare's to judge after its fetch, in
// TestPrepareJudgesTheFetchedMain.)
func TestLocateRefusesAndChangesNothing(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		break_  func(t *testing.T, f *frontFixture)
		reason  TrackerReason
		mention string
	}{
		{"a folder that is not a clone", func(t *testing.T, f *frontFixture) {
			os.RemoveAll(f.tracker_())
			os.MkdirAll(f.tracker_(), 0o755)
			os.WriteFile(filepath.Join(f.tracker_(), "a"), []byte("a"), 0o644)
		}, ReasonNotClone, ".tracker"},
		{"a link", func(t *testing.T, f *frontFixture) {
			other := filepath.Join(f.base, "elsewhere")
			os.Rename(f.tracker_(), other)
			os.Symlink(other, f.tracker_())
		}, ReasonTrackerLink, "link"},
		{"an untracked file of someone else", func(t *testing.T, f *frontFixture) {
			os.WriteFile(filepath.Join(f.tracker_(), "notes.txt"), []byte("x"), 0o644)
		}, ReasonDirty, "notes.txt"},
		{"a changed tracked file", func(t *testing.T, f *frontFixture) {
			os.WriteFile(filepath.Join(f.tracker_(), "README.md"), []byte("mine\n"), 0o644)
		}, ReasonDirty, "README.md"},
		{"a host that tracks .tracker", func(t *testing.T, f *frontFixture) {
			p := filepath.Join(f.base, "blob")
			os.WriteFile(p, []byte("x"), 0o644)
			h := run(t, f.host, "hash-object", "-w", p)
			run(t, f.host, "update-index", "--add", "--cacheinfo", "100644,"+h+",.tracker/x")
		}, "", ".tracker/x"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			f := newFrontFixture(t)
			c.break_(t, f)
			hb, tb := hostTree(t, f.host), tree(t, f.tracker_())
			tr, err := Locate(f.host)
			if tr != nil || err == nil {
				t.Fatalf("want a refusal, got %v, %v", tr, err)
			}
			if c.reason == "" { // CheckHost's own refusal, passed through
				var u *UnusualHost
				if !errors.As(err, &u) || u.Reason != ReasonTracked || !strings.Contains(err.Error(), c.mention) {
					t.Fatalf("want the host's tracked-zn-folder refusal, got %v", err)
				}
			} else {
				refusal(t, err, c.reason, c.mention)
			}
			sameTree(t, "the host", hb, hostTree(t, f.host))
			sameTree(t, "the tracker", tb, tree(t, f.tracker_()))
			if _, err := os.Lstat(f.standing()); err == nil {
				t.Error("a standing worktree was made")
			}
		})
	}
}

// A: Prepare makes the standing worktree at the fetched origin/main, links the engine's folders into it and hides
// the links in the tracker's own exclude file. Nothing in the host changes, and the tracker is clean afterwards.
func TestPrepareMakesTheStandingWorktree(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	tr, err := Locate(f.host)
	if err != nil || tr == nil {
		t.Fatalf("%v %v", tr, err)
	}
	hostBefore := hostTree(t, f.host)
	hostSnap := snap(t, f.open())
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	w := f.standing()
	if got, want := run(t, w, "rev-parse", "HEAD"), run(t, f.tracker, "rev-parse", "main"); got != want {
		t.Errorf("the standing worktree is at %s, the tracker's main is %s", got, want)
	}
	if b := run(t, w, "branch", "--show-current"); b != "" {
		t.Errorf("the standing worktree is on branch %q, want detached", b)
	}
	for _, n := range []string{"engine", "lib", "vendor", "templates", "roots.luau", "affected.luau"} {
		got, err := os.Readlink(filepath.Join(w, "z-nile", n))
		if err != nil || got != filepath.Join(f.payload, "z-nile", n) {
			t.Errorf("z-nile/%s links to %q (%v)", n, got, err)
		}
	}
	for _, where := range []string{w, f.tracker_()} {
		if st := run(t, where, "status", "--porcelain"); st != "" {
			t.Errorf("tracker status in %s: %q", where, st)
		}
	}
	if st := run(t, f.host, "status", "--porcelain"); st != "" {
		t.Errorf("host status: %q", st)
	}
	sameTree(t, "the host", hostBefore, hostTree(t, f.host))
	if d := Diff(hostSnap, snap(t, f.open())); len(d) != 0 {
		t.Errorf("the host's refs or config changed: %v", d)
	}
}

// A: a second Prepare changes nothing, a moved origin/main is followed, and a moved payload re-points the links.
func TestPrepareIsIdempotentAndFollowsTheTracker(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	tr, _ := Locate(f.host)
	if tr == nil {
		t.Fatal("no tracker")
	}
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	before := tree(t, f.tracker_())
	steps, err := tr.Prepare(f.payload)
	if err != nil || len(steps) != 0 {
		t.Fatalf("second Prepare: %v %v", steps, err)
	}
	sameTree(t, "the tracker", before, tree(t, f.tracker_()))
	// another machine pushes to the tracker
	other := filepath.Join(f.base, "other")
	run(t, f.base, "clone", "-q", f.tracker, other)
	commit(t, other, "second.txt")
	run(t, other, "push", "-q", "origin", "main")
	want := run(t, other, "rev-parse", "HEAD")
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	if got := run(t, f.standing(), "rev-parse", "HEAD"); got != want {
		t.Errorf("the standing worktree did not follow the tracker: %s, want %s", got, want)
	}
	if _, err := os.Stat(filepath.Join(f.standing(), "second.txt")); err != nil {
		t.Error("the new file is not in the standing worktree")
	}
	// a new payload folder
	np := realTemp(t)
	for _, d := range []string{"engine", "lib", "vendor", "templates"} {
		os.MkdirAll(filepath.Join(np, "z-nile", d), 0o755)
	}
	for _, n := range []string{"roots.luau", "affected.luau"} {
		os.WriteFile(filepath.Join(np, "z-nile", n), nil, 0o644)
	}
	if _, err := tr.Prepare(np); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.Readlink(filepath.Join(f.standing(), "z-nile", "engine")); got != filepath.Join(np, "z-nile", "engine") {
		t.Errorf("engine link %q after a new payload", got)
	}
	if st := run(t, f.standing(), "status", "--porcelain"); st != "" {
		t.Errorf("tracker status: %q", st)
	}
}

// A: what the engine leaves in the standing worktree (an untracked folder, an ignored cache) never stops the refresh;
// a tracked file someone changed there, or a real file where an engine link goes, stops it with the cause.
func TestPrepareRefusesWhatItCannotOverwrite(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	tr, _ := Locate(f.host)
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatal(err)
	}
	os.MkdirAll(filepath.Join(f.standing(), "upstream", ".tracker", "issues", "f0001"), 0o755)
	os.MkdirAll(filepath.Join(f.standing(), ".cache", "x"), 0o755)
	other := filepath.Join(f.base, "other")
	run(t, f.base, "clone", "-q", f.tracker, other)
	commit(t, other, "second.txt")
	run(t, other, "push", "-q", "origin", "main")
	if _, err := tr.Prepare(f.payload); err != nil {
		t.Fatalf("residue stopped the refresh: %v", err)
	}
	// a tracked file changed in the standing worktree
	readme := filepath.Join(f.standing(), "README.md")
	os.WriteFile(readme, []byte("edited\n"), 0o644)
	commit(t, other, "third.txt")
	run(t, other, "push", "-q", "origin", "main")
	_, err := tr.Prepare(f.payload)
	refusal(t, err, ReasonWorktree, "README.md")
	if got := readText(t, readme); got != "edited\n" {
		t.Errorf("the edit was lost: %q", got)
	}
	os.WriteFile(readme, nil, 0o644)
	run(t, f.standing(), "checkout", "-q", "--", "README.md")
	// a real file where a link goes
	link := filepath.Join(f.standing(), "z-nile", "engine")
	os.Remove(link)
	os.WriteFile(link, []byte("mine"), 0o644)
	_, err = tr.Prepare(f.payload)
	refusal(t, err, ReasonEngineInPlay, "z-nile/engine")
	if got := readText(t, link); got != "mine" {
		t.Errorf("the file was replaced: %q", got)
	}
}
