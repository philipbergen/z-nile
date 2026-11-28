package host

import (
	"crypto/sha256"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// initFixture is a host (the fixture's clone of an upstream with a fork remote) plus an empty bare tracker repository,
// a throwaway HOME whose git config holds an identity (zn sets none: the user's own is used), and a lookup that
// answers for the two bare repositories the way GitHub would (the fork is the user's, the upstream is not).
type initFixture struct {
	*fixture
	tracker   string
	home      string
	ownedHome bool // ownHome made home this test's own
}

// The fixture's home is the process-wide fixture HOME (TestMain: a git identity and nothing else), shared read-only by
// every parallel test; a test that writes the user's global git config takes a home of its own first (ownHome).
func newInitFixture(t *testing.T) *initFixture {
	t.Helper()
	f := newFixture(t)
	tr := filepath.Join(f.base, "tracker.git")
	if err := os.MkdirAll(tr, 0o755); err != nil {
		t.Fatal(err)
	}
	run(t, tr, "init", "-q", "--bare", "-b", "main")
	keepPacks(t, tr)
	return &initFixture{fixture: f, tracker: tr, home: os.Getenv("HOME")}
}

// ownHome gives the fixture a home of its own, a copy of the shared one, as this test's HOME and XDG_CONFIG_HOME, for a
// test that writes the user's global git config. It sets the environment, so such a test stays sequential.
func (f *initFixture) ownHome(t *testing.T) {
	t.Helper()
	if f.ownedHome {
		return
	}
	home := realTemp(t)
	if err := os.WriteFile(filepath.Join(home, ".gitconfig"), []byte(readText(t, filepath.Join(f.home, ".gitconfig"))), 0o644); err != nil {
		t.Fatal(err)
	}
	f.home, f.ownedHome = home, true
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
}

func (f *initFixture) lookup() Lookup {
	up, _ := ParseRemote(f.upstream)
	fk, _ := ParseRemote(f.fork)
	return func(id RemoteID) (Facts, error) {
		switch id.Key() {
		case up.Key():
			return Facts{}, nil
		case fk.Key():
			return Facts{Parent: &up, CanPush: true, Owned: true}, nil
		}
		return Facts{}, ErrNotServed
	}
}

func (f *initFixture) opts() InitOptions {
	return InitOptions{Root: f.host, Tracker: f.tracker, Lookup: f.lookup()}
}

// tree is every file under dir (the git directory included) with its content hash, so "unchanged" means every byte.
func tree(t *testing.T, dir string) map[string]string {
	t.Helper()
	out := map[string]string{}
	err := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(dir, p)
		switch {
		case d.Type()&fs.ModeSymlink != 0:
			l, _ := os.Readlink(p)
			out[rel] = "link " + l
		case d.IsDir():
			out[rel+"/"] = "dir"
		default:
			b, err := os.ReadFile(p)
			if err != nil {
				return err
			}
			out[rel] = fmt.Sprintf("%x", sha256.Sum256(b))
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func sameTree(t *testing.T, what string, a, b map[string]string) {
	t.Helper()
	var diff []string
	for k, v := range b {
		if a[k] != v {
			diff = append(diff, k)
		}
	}
	for k := range a {
		if _, ok := b[k]; !ok {
			diff = append(diff, k)
		}
	}
	sort.Strings(diff)
	if len(diff) > 0 {
		t.Errorf("%s changed: %v", what, diff)
	}
}

func readText(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func mustInit(t *testing.T, o InitOptions) []string {
	t.Helper()
	steps, err := Init(o)
	if err != nil {
		t.Fatal(err)
	}
	return steps
}

func joined(steps []string) string { return strings.Join(steps, "\n") }

func trackerFiles(t *testing.T, bare string) string {
	t.Helper()
	return run(t, bare, "ls-tree", "-r", "--name-only", "main")
}

// AC1: an empty tracker is cloned to <host>/.tracker with that origin, initialised (README, tracker .gitignore, the
// minimal skeleton) on main and pushed; the host's exclude gets the three lines; and the only change in the host's
// refs, config and .git files is info/exclude.
func TestInitClonesInitialisesAndPushes(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	before := snap(t, f.open())
	steps := mustInit(t, f.opts())
	for _, want := range []string{"cloned the tracker", "initialised the empty tracker", "pushed main", ".git/info/exclude"} {
		if !strings.Contains(joined(steps), want) {
			t.Errorf("steps %q do not say %q", steps, want)
		}
	}
	tr := filepath.Join(f.host, ".tracker")
	if got := run(t, tr, "config", "--get", "remote.origin.url"); got != f.tracker {
		t.Errorf("origin is %q, want the address typed %q", got, f.tracker)
	}
	files := trackerFiles(t, f.tracker)
	for _, want := range []string{"README.md", ".gitignore", "z-nile/projects.toml", "upstream/.tracker/issues/.gitkeep", "upstream/.tracker/rafts/.gitkeep"} {
		if !strings.Contains(files, want) {
			t.Errorf("the tracker holds %q, want %q", files, want)
		}
	}
	if got := run(t, f.tracker, "rev-parse", "main"); got != run(t, tr, "rev-parse", "HEAD") {
		t.Error("the tracker's main is not the clone's HEAD")
	}
	if n := run(t, f.tracker, "rev-list", "--count", "main"); n != "1" {
		t.Errorf("%s commits on the tracker, want one", n)
	}
	ign := run(t, f.tracker, "show", "main:.gitignore")
	for _, want := range []string{".cache/", "prompt.md"} {
		if !strings.Contains(ign, want) {
			t.Errorf("tracker .gitignore %q lacks %q", ign, want)
		}
	}
	// AC4: nothing of zn shows in the host, and exactly the three lines are in the exclude file, once
	if st := run(t, f.host, "status", "--porcelain"); st != "" {
		t.Errorf("host status after init: %q", st)
	}
	ex := readText(t, filepath.Join(f.host, ".git", "info", "exclude"))
	for _, l := range []string{".tracker/", ".worktree/", ".cache/"} {
		if strings.Count(ex, "\n"+l+"\n") != 1 {
			t.Errorf("exclude holds %q %d times: %q", l, strings.Count(ex, "\n"+l+"\n"), ex)
		}
	}
	changes := Diff(before, snap(t, f.open()))
	for _, c := range changes {
		if c.Kind != KindFile || c.Name != "info/exclude" {
			t.Errorf("init changed the host's .git beyond info/exclude: %s", c)
		}
	}
	if _, err := os.Stat(filepath.Join(f.host, ".gitignore")); err == nil {
		t.Error("init wrote the host's tracked .gitignore without being asked")
	}
}

// The README says what the repository is and holds nothing private: no machine name, email, local path or address.
func TestInitReadmeHoldsNothingPrivate(t *testing.T) {
	t.Parallel() // it only reads the shared HOME's path
	f := newInitFixture(t)
	mustInit(t, f.opts())
	readme := run(t, f.tracker, "show", "main:README.md")
	host, _ := os.Hostname()
	for _, bad := range []string{f.home, f.base, f.tracker, f.upstream, "@", "/Users/", "/home/", "https://", "ssh://"} {
		if bad != "" && strings.Contains(readme, bad) {
			t.Errorf("the README holds %q:\n%s", bad, readme)
		}
	}
	if host != "" && strings.Contains(strings.ToLower(readme), strings.ToLower(host)) {
		t.Errorf("the README holds the machine name %q", host)
	}
	for _, want := range []string{"upstream", "public", "work record"} {
		if !strings.Contains(readme, want) {
			t.Errorf("the README does not say %q:\n%s", want, readme)
		}
	}
	// no commit carries anything private either: the identity is the user's own noreply address, the message is fixed
	log := run(t, f.tracker, "log", "--format=%an|%ae|%s")
	if strings.Contains(log, f.home) || strings.Contains(log, f.base) {
		t.Errorf("the commit holds a local path: %s", log)
	}
}

// AC1: a second run changes nothing, in the host, the tracker clone or the tracker, and says it is set up.
func TestInitSecondRunChangesNothing(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	mustInit(t, f.opts())
	hostBefore := tree(t, f.host)
	trackerBefore := tree(t, f.tracker)
	refsBefore := run(t, f.tracker, "for-each-ref")
	steps := mustInit(t, f.opts())
	if len(steps) != 0 {
		t.Errorf("a second run took steps: %q", steps)
	}
	sameTree(t, "the host", hostBefore, tree(t, f.host))
	sameTree(t, "the tracker repository", trackerBefore, tree(t, f.tracker))
	if refsBefore != run(t, f.tracker, "for-each-ref") {
		t.Error("the tracker's refs moved")
	}
}

// A tracker that already has commits is not rewritten: its README is left alone and nothing is pushed.
func TestInitLeavesANonEmptyTrackerAlone(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	seed := filepath.Join(f.base, "tracker-seed")
	run(t, f.base, "clone", "-q", f.tracker, seed)
	if err := os.WriteFile(filepath.Join(seed, "README.md"), []byte("mine\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	os.MkdirAll(filepath.Join(seed, "z-nile"), 0o755)
	os.WriteFile(filepath.Join(seed, "z-nile", "projects.toml"), []byte("retired = []\n[[project]]\nname = \"mine\"\nroot = \"mine/.tracker\"\n"), 0o644)
	run(t, seed, "add", "README.md", "z-nile")
	run(t, seed, "commit", "-q", "-m", "mine")
	run(t, seed, "push", "-q", "origin", "main")
	head := run(t, f.tracker, "rev-parse", "main")
	steps := mustInit(t, f.opts())
	if strings.Contains(joined(steps), "initialised") || strings.Contains(joined(steps), "pushed") {
		t.Errorf("a tracker with history was touched: %q", steps)
	}
	if !strings.Contains(joined(steps), "cloned the tracker") {
		t.Errorf("steps %q do not say the clone", steps)
	}
	if run(t, f.tracker, "rev-parse", "main") != head {
		t.Error("the tracker's main moved")
	}
	if got := readText(t, filepath.Join(f.host, ".tracker", "README.md")); got != "mine\n" {
		t.Errorf("README rewritten: %q", got)
	}
}

// The one outward-facing act, the push, goes only to the address typed: the host's remotes are untouched.
func TestInitPushesOnlyToTheTypedAddress(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	up, fk := run(t, f.upstream, "for-each-ref"), run(t, f.fork, "for-each-ref")
	mustInit(t, f.opts())
	if run(t, f.upstream, "for-each-ref") != up || run(t, f.fork, "for-each-ref") != fk {
		t.Error("init pushed to a host remote")
	}
	if run(t, f.tracker, "for-each-ref") == "" {
		t.Error("nothing reached the tracker")
	}
}

// A failed push is retried by the next run, which pushes and does not initialise or commit a second time.
func TestInitRetriesAFailedPush(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	hook := filepath.Join(f.tracker, "hooks", "pre-receive")
	if err := os.WriteFile(hook, []byte("#!/bin/sh\necho no >&2\nexit 1\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := Init(f.opts()); err == nil || !strings.Contains(err.Error(), "push") {
		t.Fatalf("a refused push must be an error naming the push, got %v", err)
	}
	if got := run(t, f.tracker, "for-each-ref"); got != "" {
		t.Fatalf("the refused push left refs: %q", got)
	}
	local := run(t, filepath.Join(f.host, ".tracker"), "rev-parse", "HEAD")
	if err := os.Remove(hook); err != nil {
		t.Fatal(err)
	}
	steps := mustInit(t, f.opts())
	if strings.Contains(joined(steps), "initialised") || !strings.Contains(joined(steps), "pushed main") {
		t.Errorf("the retry should only push: %q", steps)
	}
	if run(t, f.tracker, "rev-parse", "main") != local {
		t.Error("the retry committed again instead of pushing the first commit")
	}
}

// A hook of the user's template or the tracker never runs, and the template's hooks are not copied into the clone.
func TestInitRunsNoHooks(t *testing.T) {
	f := newInitFixture(t)
	marker := filepath.Join(f.base, "marker")
	tpl := filepath.Join(f.base, "template")
	if err := os.MkdirAll(filepath.Join(tpl, "hooks"), 0o755); err != nil {
		t.Fatal(err)
	}
	body := "#!/bin/sh\necho ran >> \"" + marker + "\"\n"
	for _, h := range []string{"pre-commit", "commit-msg", "post-commit", "pre-push", "post-checkout", "reference-transaction"} {
		if err := os.WriteFile(filepath.Join(tpl, "hooks", h), []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	f.ownHome(t) // it writes the user's global git config
	cfg := readText(t, filepath.Join(f.home, ".gitconfig")) + "[init]\n\ttemplateDir = " + tpl + "\n"
	if err := os.WriteFile(filepath.Join(f.home, ".gitconfig"), []byte(cfg), 0o644); err != nil {
		t.Fatal(err)
	}
	mustInit(t, f.opts())
	if _, err := os.Stat(marker); err == nil {
		t.Fatal("a hook ran during init")
	}
	if ents, _ := os.ReadDir(filepath.Join(f.host, ".tracker", ".git", "hooks")); len(ents) != 0 {
		t.Errorf("the user's template hooks were copied into the tracker clone: %v", ents)
	}
}

// --gitignore appends the three lines to the host's tracked .gitignore instead (once, keeping what is there), leaves
// info/exclude alone and commits nothing in the host.
func TestInitGitignoreMode(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	if err := os.WriteFile(filepath.Join(f.host, ".gitignore"), []byte("build/"), 0o644); err != nil { // no final newline
		t.Fatal(err)
	}
	run(t, f.host, "add", ".gitignore")
	run(t, f.host, "commit", "-q", "-m", "ignore")
	head := run(t, f.host, "rev-parse", "HEAD")
	before := snap(t, f.open())
	o := f.opts()
	o.Gitignore = true
	steps := mustInit(t, o)
	if !strings.Contains(joined(steps), ".gitignore") || !strings.Contains(joined(steps), "not committed") {
		t.Errorf("steps %q must say the .gitignore changed and was not committed", steps)
	}
	want := "build/\n.tracker/\n.worktree/\n.cache/\n"
	if got := readText(t, filepath.Join(f.host, ".gitignore")); got != want {
		t.Errorf(".gitignore is %q, want %q", got, want)
	}
	if run(t, f.host, "rev-parse", "HEAD") != head {
		t.Error("init committed in the host")
	}
	if st := run(t, f.host, "status", "--porcelain"); st != "M .gitignore" {
		t.Errorf("status %q: only the .gitignore change should show", st)
	}
	for _, c := range Diff(before, snap(t, f.open())) {
		t.Errorf("--gitignore changed the host's .git: %s", c)
	}
	// a second run, with or without the flag, changes nothing
	hostBefore := tree(t, f.host)
	if steps := mustInit(t, o); len(steps) != 0 {
		t.Errorf("a second run took steps: %q", steps)
	}
	sameTree(t, "the host", hostBefore, tree(t, f.host))
}

// Lines the host already ignores in another spelling are not added again.
func TestInitGitignoreModeKnowsOtherSpellings(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	if err := os.WriteFile(filepath.Join(f.host, ".gitignore"), []byte("/.tracker\n.worktree\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	o := f.opts()
	o.Gitignore = true
	mustInit(t, o)
	if got := readText(t, filepath.Join(f.host, ".gitignore")); got != "/.tracker\n.worktree\n.cache/\n" {
		t.Errorf(".gitignore is %q", got)
	}
}

// refuses runs init and asserts it is refused with every word of want in the message, that the host is byte for byte
// as it was (refs, config, info/exclude, .gitignore and every other file), that no .tracker was made and that the
// tracker repository did not change.
func (f *initFixture) refuses(t *testing.T, o InitOptions, want ...string) {
	t.Helper()
	_, hasTracker := os.Lstat(filepath.Join(o.Root, ".tracker"))
	hostBefore := tree(t, o.Root)
	trackerBefore := tree(t, f.tracker)
	var snapBefore *Snapshot // the package's own proof, wherever the host can be opened at all
	if r, err := Open(o.Root, o.Root, filepath.Join(o.Root, ".cache", "nohooks")); err == nil {
		s, err := r.Snapshot()
		if err != nil {
			t.Fatal(err)
		}
		snapBefore = &s
	}
	_, err := Init(o)
	if err == nil {
		t.Fatalf("init was not refused (want %v)", want)
	}
	for _, w := range want {
		if !strings.Contains(strings.ToLower(err.Error()), strings.ToLower(w)) {
			t.Errorf("the refusal %q does not name %q", err, w)
		}
	}
	sameTree(t, "the host", hostBefore, tree(t, o.Root))
	sameTree(t, "the tracker repository", trackerBefore, tree(t, f.tracker))
	if snapBefore != nil {
		r, _ := Open(o.Root, o.Root, filepath.Join(o.Root, ".cache", "nohooks"))
		after, err := r.Snapshot()
		if err != nil {
			t.Fatal(err)
		}
		if d := Diff(*snapBefore, after); len(d) != 0 {
			t.Errorf("a refusal changed the host's refs, config or .git files: %v", d)
		}
	}
	if _, now := os.Lstat(filepath.Join(o.Root, ".tracker")); (hasTracker == nil) != (now == nil) {
		t.Error("a refused init created or removed .tracker")
	}
}

// AC2 with the package's own snapshot: a refused init leaves the host's refs, config and .git files unchanged.
func TestInitRefusalLeavesTheSnapshotUnchanged(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	before := snap(t, f.open())
	o := f.opts()
	o.Tracker = "https://someone:ghp_secretsecretsecret@github.com/o/r.git"
	if _, err := Init(o); err == nil {
		t.Fatal("refused nothing")
	}
	if d := Diff(before, snap(t, f.open())); len(d) != 0 {
		t.Errorf("a refusal changed the host: %v", d)
	}
}

func TestInitRefusesACredentialInTheTrackerAddress(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	o := f.opts()
	o.Tracker = "https://someone:ghp_secretsecretsecret@github.com/o/r.git"
	_, err := Init(o)
	if err == nil {
		t.Fatal("not refused")
	}
	for _, secret := range []string{"ghp_secret", "someone"} {
		if strings.Contains(err.Error(), secret) {
			t.Errorf("the refusal shows part of the address: %v", err)
		}
	}
	f.refuses(t, o, "credential")
}

func TestInitRefusesOtherUnsafeTrackerAddresses(t *testing.T) {
	t.Parallel()
	for _, a := range []string{"", "ext::sh -c evil", "--upload-pack=evil", "ftp://example.com/o/r", "relative/path"} {
		f := newInitFixture(t)
		o := f.opts()
		o.Tracker = a
		f.refuses(t, o, "tracker address")
	}
}

// The tracker repository must not be a repository of the host, or the push would put zn's tracker into the host.
func TestInitRefusesATrackerThatIsAHostRemote(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	for _, addr := range []string{f.upstream, f.fork} {
		o := f.opts()
		o.Tracker = addr
		f.refuses(t, o, "tracker", "remote")
	}
}

func TestInitRefusesTheUnusualHosts(t *testing.T) { // sequential: it sets the walk seam every CheckHost reads
	t.Run("submodule", func(t *testing.T) {
		f := newInitFixture(t)
		run(t, f.host, "-c", "protocol.file.allow=always", "submodule", "add", "-q", f.seed, "vendor/sub")
		o := f.opts()
		o.Root = filepath.Join(f.host, "vendor", "sub")
		f.refuses(t, o, "submodule")
	})
	t.Run("separate git dir", func(t *testing.T) {
		f := newInitFixture(t)
		sep := filepath.Join(f.base, "sep")
		run(t, f.base, "clone", "-q", "--separate-git-dir", filepath.Join(f.base, "sep.gitdir"), f.upstream, sep)
		o := f.opts()
		o.Root = sep
		f.refuses(t, o, "main checkout")
	})
	t.Run("bare host with worktrees", func(t *testing.T) {
		f := newInitFixture(t)
		run(t, f.upstream, "worktree", "add", "-q", "-b", "side", filepath.Join(f.base, "bare-wt"))
		o := f.opts()
		o.Root = f.upstream
		f.refuses(t, o, "bare")
	})
	t.Run("not a repository", func(t *testing.T) {
		f := newInitFixture(t)
		stopWalkAt(t, f.base)
		d := filepath.Join(f.base, "plain")
		os.MkdirAll(d, 0o755)
		o := f.opts()
		o.Root = d
		f.refuses(t, o, "not a git repository")
	})
	t.Run("program-running local config", func(t *testing.T) {
		f := newInitFixture(t)
		run(t, f.host, "config", "core.sshCommand", "touch never")
		f.refuses(t, f.opts(), "core.sshCommand")
	})
	t.Run("the host tracks .tracker", func(t *testing.T) {
		f := newInitFixture(t)
		if err := os.MkdirAll(filepath.Join(f.host, ".tracker"), 0o755); err != nil {
			t.Fatal(err)
		}
		commit(t, f.host, filepath.Join(".tracker", "x"))
		f.refuses(t, f.opts(), "tracks", ".tracker")
	})
}

// A host with no remote it can use is refused by step 2's Roles, with no remote name asked for.
func TestInitRefusesWhenTheRolesCannotBeWorkedOut(t *testing.T) {
	t.Parallel()
	t.Run("no remote", func(t *testing.T) {
		f := newInitFixture(t)
		run(t, f.host, "remote", "remove", "origin")
		run(t, f.host, "remote", "remove", "fork")
		f.refuses(t, f.opts(), "no remote")
	})
	t.Run("nobody is signed in", func(t *testing.T) {
		f := newInitFixture(t)
		o := f.opts()
		o.Lookup = func(RemoteID) (Facts, error) { return Facts{}, ErrNotSignedIn }
		f.refuses(t, o, "gh auth login")
	})
	t.Run("an override that is not a remote", func(t *testing.T) {
		f := newInitFixture(t)
		o := f.opts()
		o.Overrides = Overrides{Fork: "nope"}
		f.refuses(t, o, "nope")
	})
}

func TestInitRefusesAnExistingTrackerThatIsNotACloneOfTheAddress(t *testing.T) {
	t.Parallel()
	t.Run("another repository", func(t *testing.T) {
		f := newInitFixture(t)
		other := filepath.Join(f.base, "other.git")
		os.MkdirAll(other, 0o755)
		run(t, other, "init", "-q", "--bare", "-b", "main")
		run(t, f.base, "clone", "-q", other, filepath.Join(f.host, ".tracker"))
		f.refuses(t, f.opts(), ".tracker", "not a clone")
	})
	t.Run("a plain folder", func(t *testing.T) {
		f := newInitFixture(t)
		os.MkdirAll(filepath.Join(f.host, ".tracker", "x"), 0o755)
		f.refuses(t, f.opts(), ".tracker", "not the top of its own git repository")
	})
	t.Run("a file", func(t *testing.T) {
		f := newInitFixture(t)
		os.WriteFile(filepath.Join(f.host, ".tracker"), []byte("x"), 0o644)
		f.refuses(t, f.opts(), ".tracker is a file")
	})
	t.Run("a symbolic link", func(t *testing.T) {
		f := newInitFixture(t)
		clone := filepath.Join(f.base, "elsewhere")
		run(t, f.base, "clone", "-q", f.tracker, clone)
		if err := os.Symlink(clone, filepath.Join(f.host, ".tracker")); err != nil {
			t.Fatal(err)
		}
		f.refuses(t, f.opts(), ".tracker", "link")
	})
	t.Run("a .git that is a file", func(t *testing.T) {
		f := newInitFixture(t)
		os.MkdirAll(filepath.Join(f.host, ".tracker"), 0o755)
		os.WriteFile(filepath.Join(f.host, ".tracker", ".git"), []byte("gitdir: ../../elsewhere\n"), 0o644)
		f.refuses(t, f.opts(), ".tracker", "not the top of its own git repository")
	})
	t.Run("a .git folder git cannot read", func(t *testing.T) {
		f := newInitFixture(t)
		os.MkdirAll(filepath.Join(f.host, ".tracker", ".git"), 0o755)
		f.refuses(t, f.opts(), ".tracker", "cannot be read")
	})
	t.Run("a repository whose remote is not named origin", func(t *testing.T) {
		f := newInitFixture(t)
		clone := filepath.Join(f.host, ".tracker")
		run(t, f.base, "clone", "-q", "-o", "up", f.tracker, clone)
		f.refuses(t, f.opts(), ".tracker", "origin")
	})
	t.Run("a clone whose config would run a program", func(t *testing.T) {
		f := newInitFixture(t)
		clone := filepath.Join(f.host, ".tracker")
		run(t, f.base, "clone", "-q", f.tracker, clone)
		run(t, clone, "config", "core.sshCommand", "touch never")
		f.refuses(t, f.opts(), ".tracker", "core.sshCommand")
	})
}

// An existing clone of the right address in any spelling is accepted, and a missing host exclude is made.
func TestInitAcceptsAnExistingCloneOfTheAddress(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	run(t, f.base, "clone", "-q", f.tracker, filepath.Join(f.host, ".tracker"))
	o := f.opts()
	o.Tracker = "file://" + f.tracker // another spelling of the same repository
	steps := mustInit(t, o)
	if strings.Contains(joined(steps), "cloned") {
		t.Errorf("cloned again: %q", steps)
	}
	if !strings.Contains(joined(steps), "initialised") {
		t.Errorf("an existing clone of an empty tracker should still be initialised: %q", steps)
	}
}

// The exclude and .gitignore files must be regular files of the host: a link could lead the write outside it.
func TestInitRefusesLinkedIgnoreFiles(t *testing.T) {
	t.Parallel()
	t.Run("info/exclude", func(t *testing.T) {
		f := newInitFixture(t)
		out := filepath.Join(f.base, "outside")
		os.WriteFile(out, []byte("keep\n"), 0o644)
		p := filepath.Join(f.host, ".git", "info", "exclude")
		os.Remove(p)
		if err := os.Symlink(out, p); err != nil {
			t.Fatal(err)
		}
		f.refuses(t, f.opts(), "exclude", "link")
		if readText(t, out) != "keep\n" {
			t.Error("the file outside the host changed")
		}
	})
	t.Run(".gitignore", func(t *testing.T) {
		f := newInitFixture(t)
		out := filepath.Join(f.base, "outside")
		os.WriteFile(out, []byte("keep\n"), 0o644)
		if err := os.Symlink(out, filepath.Join(f.host, ".gitignore")); err != nil {
			t.Fatal(err)
		}
		run(t, f.host, "add", ".gitignore")
		run(t, f.host, "commit", "-q", "-m", "link")
		o := f.opts()
		o.Gitignore = true
		f.refuses(t, o, ".gitignore", "link")
		if readText(t, out) != "keep\n" {
			t.Error("the file outside the host changed")
		}
	})
}

// A fork cloned with no upstream remote still works: the upstream is the parent GitHub reports, no remote is added,
// and init writes nothing in the host's .git but info/exclude. The project is named after that upstream.
func TestInitHostWithOnlyTheForkAsRemote(t *testing.T) {
	t.Parallel()
	f := newInitFixture(t)
	run(t, f.host, "remote", "remove", "origin")
	run(t, f.host, "remote", "remove", "fork")
	run(t, f.host, "remote", "add", "origin", "https://github.com/me/omarchy.git")
	fork, _ := ParseRemote("https://github.com/me/omarchy.git")
	parent, _ := ParseRemote("https://github.com/basecamp/omarchy.git")
	o := f.opts()
	o.Lookup = func(id RemoteID) (Facts, error) {
		if id.Same(fork) {
			return Facts{Parent: &parent, CanPush: true, Owned: true}, nil
		}
		return Facts{}, ErrNotServed
	}
	before := snap(t, f.open())
	steps := mustInit(t, o)
	if !strings.Contains(joined(steps), "cloned the tracker") {
		t.Errorf("steps %q", steps)
	}
	for _, c := range Diff(before, snap(t, f.open())) {
		if c.Kind != KindFile || c.Name != "info/exclude" {
			t.Errorf("init changed the host's .git beyond info/exclude: %s", c)
		}
	}
	if !strings.Contains(trackerFiles(t, f.tracker), "omarchy/.tracker/issues/.gitkeep") {
		t.Errorf("the project is not named after the upstream repository: %s", trackerFiles(t, f.tracker))
	}
}

func TestProjectName(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"omarchy": "omarchy", "Omarchy": "omarchy", "my_repo.v2": "my-repo-v2", "/tmp/x/Up Stream": "up-stream",
		"/a/b/Foo": "foo", "/x/upstream.git": "upstream", "1password-cli": "p-1password-cli", "9": "p-9", "a--b": "a-b",
	} {
		got, err := projectName(in)
		if err != nil || got != want {
			t.Errorf("projectName(%q) = %q, %v, want %q", in, got, err, want)
		}
		if err := checkProjectName(got); err != nil {
			t.Errorf("projectName(%q) = %q, which the engine's grammar refuses: %v", in, got, err)
		}
	}
	for _, in := range []string{"", "---", "z-nile", "caf\u00e9", "tracker", "src", "/a/z-nile.git"} {
		if got, err := projectName(in); err == nil {
			t.Errorf("projectName(%q) = %q, want a refusal", in, got)
		}
	}
	for _, n := range []string{"ok", "a-b", "a1", "x"} {
		if err := checkProjectName(n); err != nil {
			t.Errorf("%q refused: %v", n, err)
		}
	}
	for _, n := range []string{"", "1a", "A", "a_b", "a--b", "-a", "a-", "z-nile", "tracker", "a b", "a/b"} {
		if err := checkProjectName(n); err == nil {
			t.Errorf("%q accepted", n)
		}
	}
}
