package host

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
)

// fixture is a host clone with an upstream (origin) that has moved on since the clone, and a fork remote. Every path
// is absolute and under one temp folder; every git call names its folder with -C and runs with a scrubbed environment.
type fixture struct {
	t        *testing.T
	base     string
	upstream string
	fork     string
	host     string
	seed     string
}

func realTemp(t *testing.T) string {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return d
}

// run runs git in dir with the scrubbed environment plus an identity for commits; dir is always passed as -C.
func run(t *testing.T, dir string, args ...string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), gitTimeout) // bounded, like every process a test starts
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(readEnv(os.Environ(), ""),
		"GIT_TEMPLATE_DIR="+fixtureGitTemplate(), // c0179: a fixture repository starts with two files of its template, not fourteen
		"GIT_AUTHOR_NAME=t", "GIT_AUTHOR_EMAIL=t@example.invalid",
		"GIT_COMMITTER_NAME=t", "GIT_COMMITTER_EMAIL=t@example.invalid")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git -C %s %s: %v\n%s", dir, strings.Join(args, " "), err, out)
	}
	return strings.TrimSpace(string(out))
}

// fixtureGitTemplate is the init template of every fixture repository (c0179): the one hook sample and the exclude file
// the tests name, instead of git's seventy-odd files per repository that every test copies and removes again. TestMain
// makes it, in a folder of its own, and the test helpers' own git calls take it through GIT_TEMPLATE_DIR. No git config names it: the HOME the code under test sees holds an identity only (c0179 review F1).
var fixtureGitTemplatePath string

var fixtureGitTemplateOnce sync.Once

// fixtureGitTemplate is that folder, made on first use: the helper processes the tests start run TestMain too and must leave
// nothing behind. A failure to make it stops the run.
func fixtureGitTemplate() string {
	fixtureGitTemplateOnce.Do(func() {
		d, err := os.MkdirTemp("", "zn-gittemplate-")
		if err == nil {
			fixtureGitTemplatePath = d
			err = makeGitTemplate(d)
		}
		if err != nil {
			panic(fmt.Sprintf("the git template of the fixtures could not be made: %v", err))
		}
	})
	return fixtureGitTemplatePath
}

// makeGitTemplate writes the fixture init template under dir.
func makeGitTemplate(dir string) error {
	for p, body := range map[string]string{"hooks/pre-commit.sample": "#!/bin/sh\n", "info/exclude": "# fixture\n"} {
		if err := os.MkdirAll(filepath.Dir(filepath.Join(dir, p)), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(dir, p), []byte(body), 0o644); err != nil {
			return err
		}
	}
	return nil
}

// keepPacks makes each bare repository keep what is pushed to it as a pack and not as a file per object, in its own local
// config (the remote's side only: neither the host's nor the tracker clone's config, nor the user's, is touched: c0179 F1).
func keepPacks(t *testing.T, repos ...string) {
	t.Helper()
	for _, r := range repos {
		run(t, r, "config", "receive.unpackLimit", "1")
	}
}

// pack turns the loose objects and refs of each repository (a folder with its own git directory or a bare one) into one
// pack, so a copy of the fixture holds a few large files instead of a file per object (c0179).
func pack(t *testing.T, repos ...string) {
	t.Helper()
	for _, r := range repos {
		// repack and pack-refs, not gc: gc also writes a commit graph, info/refs and a reverse index, four more files each
		run(t, r, "-c", "gc.auto=0", "-c", "repack.writeBitmaps=false", "-c", "pack.writeReverseIndex=false", "repack", "-a", "-d", "-q")
		run(t, r, "pack-refs", "--all")
	}
}

func commit(t *testing.T, dir, file string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, file), []byte(file), 0o644); err != nil {
		t.Fatal(err)
	}
	run(t, dir, "add", file)
	run(t, dir, "commit", "-q", "-m", file)
}

// fixtureTemplate is one fixture built once per test binary and kept outside every test's temp folder: each test
// copies it instead of running the fixture's fifteen-odd git commands. base is where it was built, which the copies'
// git config files name and are rewritten from (fixtureConfigs).
var fixtureTemplate struct {
	once      sync.Once
	dir, base string
	err       error
}

// fixtureConfigs are the git config files of a fixture that name its repositories by absolute path.
var fixtureConfigs = []string{"host/.git/config", "seed/.git/config"}

// newFixture is a copy of the fixture template: it sets no variable, so a parallel test may make one.
func newFixture(t *testing.T) *fixture {
	t.Helper()
	tp := &fixtureTemplate
	tp.once.Do(func() {
		f := buildFixture(t, realTemp(t))
		tp.base = f.base
		if tp.dir, tp.err = os.MkdirTemp("", "zn-host-fixture-"); tp.err == nil {
			tp.err = copyTree(f.base, filepath.Join(tp.dir, "base"))
		}
	})
	if tp.err != nil || tp.dir == "" {
		t.Fatalf("the fixture template could not be built (%v): see the first test that built it", tp.err)
	}
	base := filepath.Join(realTemp(t), "base")
	if err := copyTree(filepath.Join(tp.dir, "base"), base); err != nil {
		t.Fatal(err)
	}
	rebase(t, base, tp.base, fixtureConfigs)
	return &fixture{t: t, base: base,
		upstream: filepath.Join(base, "upstream.git"), fork: filepath.Join(base, "fork.git"),
		host: filepath.Join(base, "host"), seed: filepath.Join(base, "seed")}
}

// rebase points the copied config files, which name the repositories by absolute path, from old to base.
func rebase(t *testing.T, base, old string, configs []string) {
	t.Helper()
	for _, cfg := range configs {
		p := filepath.Join(base, cfg)
		b, err := os.ReadFile(p)
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(strings.ReplaceAll(string(b), old, base)), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

// fixtureBuilds counts how many times a fixture was built from scratch in this test binary: the template means once (c0179).
var fixtureBuilds atomic.Int32

// buildFixture makes the fixture in base: what newFixture copies.
func buildFixture(t *testing.T, base string) *fixture {
	t.Helper()
	fixtureBuilds.Add(1)
	f := &fixture{t: t, base: base,
		upstream: filepath.Join(base, "upstream.git"), fork: filepath.Join(base, "fork.git"),
		host: filepath.Join(base, "host"), seed: filepath.Join(base, "seed")}
	for _, d := range []string{f.upstream, f.fork, f.seed} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	run(t, f.upstream, "init", "-q", "--bare", "-b", "main")
	run(t, f.fork, "init", "-q", "--bare", "-b", "main")
	keepPacks(t, f.upstream, f.fork)
	run(t, f.seed, "init", "-q", "-b", "main")
	run(t, f.seed, "config", "core.logAllRefUpdates", "false") // nothing reads the seed's reflogs: fifteen files fewer per copy (c0179)
	run(t, f.seed, "remote", "add", "origin", f.upstream)
	commit(t, f.seed, "a")
	run(t, f.seed, "tag", "v1")
	run(t, f.seed, "push", "-q", "origin", "main", "v1")
	run(t, base, "clone", "-q", f.upstream, f.host)
	run(t, f.host, "remote", "add", "fork", f.fork)
	// the upstream moves on after the clone: a commit on main, a tag and another branch
	commit(t, f.seed, "b")
	run(t, f.seed, "tag", "v2")
	run(t, f.seed, "branch", "topic")
	run(t, f.seed, "push", "-q", "origin", "main", "v2", "topic")
	pack(t, f.upstream, f.fork, f.seed, f.host)
	return f
}

func (f *fixture) open() *Repo {
	f.t.Helper()
	r, err := Open(f.host, f.host, filepath.Join(f.host, ".cache", "nohooks"))
	if err != nil {
		f.t.Fatal(err)
	}
	return r
}

func snap(t *testing.T, r *Repo) Snapshot {
	t.Helper()
	s, err := r.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	return s
}

const branch = "zn/R0001-thing"

// delivery is the designed delivery of these tests.
func delivery(wt string) Delivery {
	return Delivery{Remote: "origin", Default: "main", Branch: branch, WorktreeName: wt}
}

// violations renders what Allowed rejects, one change per line.
func violations(changes []Change, d Delivery) string {
	var out []string
	for _, c := range Allowed(changes, d) {
		out = append(out, c.String())
	}
	return strings.Join(out, "\n")
}

// AC5 for worktree: the diff after the designed fetch-and-worktree equals exactly the designed list.
func TestSnapshotDelivery(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	r := f.open()
	before := snap(t, r)
	mainBefore := run(t, f.host, "rev-parse", "main")
	wt := filepath.Join(f.host, ".worktree", "R0001")
	if err := r.FetchAndWorktree("origin", "main", branch, wt); err != nil {
		t.Fatal(err)
	}
	after := snap(t, r)
	changes := Diff(before, after)

	if bad := violations(changes, delivery("R0001")); bad != "" {
		t.Fatalf("writes outside the design:\n%s", bad)
	}
	var refs, cfg []string
	for _, c := range changes {
		switch c.Kind {
		case KindRef:
			refs = append(refs, c.Name)
		case KindConfig:
			cfg = append(cfg, c.Name)
		}
	}
	want := "refs/heads/" + branch + " refs/remotes/origin/main"
	if got := strings.Join(refs, " "); got != want {
		t.Fatalf("ref changes = %q, want %q", got, want)
	}
	if len(cfg) != 0 {
		t.Fatalf("config changes %v, want none (no upstream settings)", cfg)
	}
	upstreamMain := run(t, f.upstream, "rev-parse", "main")
	if after.Refs["refs/heads/"+branch] != upstreamMain || after.Refs["refs/remotes/origin/main"] != upstreamMain {
		t.Fatalf("branch %s / origin/main are not at the upstream main %s", after.Refs["refs/heads/"+branch], upstreamMain)
	}
	if run(t, f.host, "rev-parse", "main") != mainBefore {
		t.Fatal("the local default branch moved")
	}
	for name := range after.Refs {
		if strings.HasPrefix(name, "refs/tags/") && name != "refs/tags/v1" {
			t.Fatalf("a tag came in: %s", name)
		}
	}
	if _, ok := after.Refs["refs/remotes/origin/topic"]; ok {
		t.Fatal("another origin branch came in")
	}
	if got := run(t, wt, "rev-parse", "--abbrev-ref", "HEAD"); got != branch {
		t.Fatalf("worktree is on %q", got)
	}
	if _, err := os.Stat(filepath.Join(wt, "b")); err != nil {
		t.Fatalf("worktree lacks the fetched commit's file: %v", err)
	}
}

// Mutants: a plain `git fetch origin` and a tracking worktree each break the same list.
func TestMutantsAreCaught(t *testing.T) {
	t.Parallel()
	t.Run("plain fetch", func(t *testing.T) {
		f := newFixture(t)
		r := f.open()
		before := snap(t, r)
		run(t, f.host, "fetch", "origin")
		wt := filepath.Join(f.host, ".worktree", "R0001")
		run(t, f.host, "worktree", "add", "--no-track", "-b", branch, wt, "refs/remotes/origin/main")
		bad := violations(Diff(before, snap(t, r)), delivery("R0001"))
		if !strings.Contains(bad, "refs/tags/v2") || !strings.Contains(bad, "refs/remotes/origin/topic") {
			t.Fatalf("plain fetch not caught:\n%s", bad)
		}
	})
	t.Run("tracking worktree", func(t *testing.T) {
		f := newFixture(t)
		r := f.open()
		before := snap(t, r)
		if err := r.FetchDefault("origin", "main"); err != nil {
			t.Fatal(err)
		}
		wt := filepath.Join(f.host, ".worktree", "R0001")
		run(t, f.host, "worktree", "add", "--track", "-b", branch, wt, "refs/remotes/origin/main")
		bad := violations(Diff(before, snap(t, r)), delivery("R0001"))
		if !strings.Contains(bad, "branch."+branch+".remote") || !strings.Contains(bad, "branch."+branch+".merge") {
			t.Fatalf("tracking worktree not caught:\n%s", bad)
		}
	})
	t.Run("pull moves the local default branch", func(t *testing.T) {
		f := newFixture(t)
		r := f.open()
		before := snap(t, r)
		run(t, f.host, "pull", "-q", "--ff-only", "--no-tags", "origin", "main")
		bad := violations(Diff(before, snap(t, r)), delivery("R0001"))
		if !strings.Contains(bad, "refs/heads/main") {
			t.Fatalf("a moved default branch not caught:\n%s", bad)
		}
	})
}

// Two reads of an unchanged repository are equal.
func TestSnapshotStable(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	r := f.open()
	a, b := snap(t, r), snap(t, r)
	if d := Diff(a, b); len(d) != 0 {
		t.Fatalf("two reads differ: %v", d)
	}
	if len(a.Refs) == 0 || len(a.Config) == 0 {
		t.Fatalf("empty snapshot: %d refs, %d config", len(a.Refs), len(a.Config))
	}
	beyond := 0
	for name := range a.Files {
		if !strings.HasPrefix(name, "refs/") && !strings.HasPrefix(name, "logs/") {
			beyond++
		}
	}
	for _, must := range []string{"HEAD", "config", "packed-refs", "info/exclude"} {
		if _, ok := a.Files[must]; !ok {
			t.Fatalf("the snapshot lacks .git/%s (%d files beyond refs)", must, beyond)
		}
	}
	if beyond < 5 {
		t.Fatalf("only %d files beyond refs/ and logs/", beyond)
	}
}

// Packed and loose refs are both seen, and packing does not change any ref.
func TestPackedAndLooseRefs(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	r := f.open()
	run(t, f.host, "pack-refs", "--all")
	packed := snap(t, r)
	for _, name := range []string{"refs/heads/main", "refs/remotes/origin/main", "refs/tags/v1"} {
		if packed.Refs[name] == "" {
			t.Fatalf("packed ref %s not seen", name)
		}
	}
	run(t, f.host, "branch", "loose")
	loose := snap(t, r)
	if loose.Refs["refs/heads/loose"] == "" {
		t.Fatal("loose ref not seen")
	}
	d := Diff(packed, loose)
	var refs []string
	for _, c := range d {
		if c.Kind == KindRef {
			refs = append(refs, c.Name)
		}
	}
	if strings.Join(refs, " ") != "refs/heads/loose" {
		t.Fatalf("ref diff = %v", refs)
	}
	run(t, f.host, "pack-refs", "--all")
	for _, c := range Diff(loose, snap(t, r)) {
		if c.Kind == KindRef {
			t.Fatalf("packing changed a ref: %s", c)
		}
	}
}

// A config key written elsewhere shows in the diff, as an addition, a change and a removal.
func TestConfigWriteShows(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	r := f.open()
	a := snap(t, r)
	run(t, f.host, "config", "branch.main.remote", "fork")
	run(t, f.host, "config", "--add", "remote.origin.fetch", "+refs/heads/x:refs/remotes/origin/x")
	b := snap(t, r)
	got := map[string]Change{}
	for _, c := range Diff(a, b) {
		if c.Kind == KindConfig {
			got[c.Name] = c
		}
	}
	if c := got["branch.main.remote"]; c.Old != "origin" || c.New != "fork" {
		t.Fatalf("changed key: %+v", c)
	}
	if c, ok := got["remote.origin.fetch"]; !ok || !strings.Contains(c.New, "refs/heads/x") {
		t.Fatalf("added value of a multi-valued key: %+v", c)
	}
	run(t, f.host, "config", "--unset", "branch.main.remote")
	removed := false
	for _, c := range Diff(b, snap(t, r)) {
		removed = removed || (c.Kind == KindConfig && c.Name == "branch.main.remote" && c.New == "")
	}
	if !removed {
		t.Fatal("removed key not shown")
	}
}

// The helper refuses a path outside the root the caller passed, and writes nothing there.
func TestRefusesOutsideRoot(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	outside := realTemp(t)
	other := filepath.Join(outside, "other")
	if err := os.MkdirAll(other, 0o755); err != nil {
		t.Fatal(err)
	}
	run(t, other, "init", "-q", "-b", "main")
	commit(t, other, "o")
	otherBefore, err := Open(other, other, filepath.Join(other, ".cache", "nohooks"))
	if err != nil {
		t.Fatal(err)
	}
	ob := snap(t, otherBefore)

	if _, err := Open(f.host, other, filepath.Join(f.host, ".cache", "nohooks")); err == nil || !strings.Contains(err.Error(), "not inside the allowed root") {
		t.Fatalf("Open outside root: %v", err)
	}
	link := filepath.Join(f.host, "link")
	if err := os.Symlink(other, link); err != nil {
		t.Fatal(err)
	}
	if _, err := Open(f.host, link, filepath.Join(f.host, ".cache", "nohooks")); err == nil {
		t.Fatal("Open through a symlink out of the root was allowed")
	}

	r := f.open()
	if err := r.FetchDefault("origin", "main"); err != nil {
		t.Fatal(err)
	}
	before := snap(t, r)
	for _, p := range []string{
		filepath.Join(outside, "wt"),
		filepath.Join(f.host, "..", "wt-escape"),
		filepath.Join(f.host, "..", "..", "wt-escape2"),
		filepath.Join(link, "wt"),
	} {
		if err := r.AddWorktree(p, "zn/x", "refs/remotes/origin/main"); err == nil || !strings.Contains(err.Error(), "not inside the allowed root") {
			t.Fatalf("AddWorktree(%s): %v", p, err)
		}
	}
	if d := Diff(before, snap(t, r)); len(d) != 0 {
		t.Fatalf("a refused call wrote: %v", d)
	}
	if d := Diff(ob, snap(t, otherBefore)); len(d) != 0 {
		t.Fatalf("the repository outside the root changed: %v", d)
	}
	for _, p := range []string{filepath.Join(outside, "wt"), filepath.Join(other, "wt")} {
		if _, err := os.Stat(p); err == nil {
			t.Fatalf("%s was created", p)
		}
	}
}

// Inherited GIT_* variables and the user's global git config neither steer nor are written by the helper.
func TestEnvironmentIsScrubbed(t *testing.T) {
	f := newFixture(t)
	decoy := realTemp(t)
	run(t, decoy, "init", "-q", "-b", "main")
	global := filepath.Join(decoy, "gitconfig")
	// if the global config leaked in, this rewrites the upstream path to nowhere and the fetch fails
	body := "[url \"" + decoy + "/nowhere\"]\n\tinsteadOf = " + f.upstream + "\n"
	if err := os.WriteFile(global, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("GIT_DIR", filepath.Join(decoy, ".git"))
	t.Setenv("GIT_WORK_TREE", decoy)
	t.Setenv("GIT_INDEX_FILE", filepath.Join(decoy, "idx"))
	t.Setenv("GIT_CONFIG_GLOBAL", global)
	t.Setenv("GIT_CONFIG_COUNT", "1")
	t.Setenv("GIT_CONFIG_KEY_0", "core.bare")
	t.Setenv("GIT_CONFIG_VALUE_0", "true")
	decoyBefore := snap(t, mustOpen(t, decoy, decoy))

	r := f.open()
	if err := r.FetchAndWorktree("origin", "main", branch, filepath.Join(f.host, ".worktree", "R1")); err != nil {
		t.Fatalf("an inherited variable leaked into git: %v", err)
	}
	if d := Diff(decoyBefore, snap(t, mustOpen(t, decoy, decoy))); len(d) != 0 {
		t.Fatalf("the decoy repository changed: %v", d)
	}
	if b, _ := os.ReadFile(global); string(b) != body {
		t.Fatal("the global config file was written")
	}
	for _, kv := range readEnv([]string{"GIT_DIR=x", "GIT_CONFIG_COUNT=1", "PATH=/bin", "HOME=/h"}, "") {
		if strings.HasPrefix(kv, "GIT_DIR=") || strings.HasPrefix(kv, "GIT_CONFIG_COUNT=") {
			t.Fatalf("kept %s", kv)
		}
	}
}

func mustOpen(t *testing.T, root, dir string) *Repo {
	t.Helper()
	r, err := Open(root, dir, filepath.Join(dir, ".cache", "nohooks"))
	if err != nil {
		t.Fatal(err)
	}
	return r
}

// A branch or remote name git would read as an option, or that is not a name, is refused with its reason before git runs.
func TestRefusesOptionLikeNames(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	r := f.open()
	before := snap(t, r)
	for _, c := range []struct{ remote, def, br, want string }{
		{"-x", "main", "b", `remote "-x" is not usable`},
		{"origin", "-x", "b", `default branch "-x" is not usable`},
		{"origin", "main", "-b", `branch "-b" is not usable`},
		{"origin", "main", "a b", `branch "a b" is not a valid branch name`},
		{"", "main", "b", `remote "" is not usable`},
		{"../upstream.git", "main", "b", `remote "../upstream.git" is not a configured remote`},
		{"nosuch", "main", "b", `remote "nosuch" is not a configured remote`},
	} {
		err := r.FetchAndWorktree(c.remote, c.def, c.br, filepath.Join(f.host, ".worktree", "R9"))
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Fatalf("%+v: got %v", c, err)
		}
	}
	if d := Diff(before, snap(t, r)); len(d) != 0 {
		t.Fatalf("a refused call wrote: %v", d)
	}
}

// A symbolic ref is recorded by its target, so retargeting origin/HEAD shows and a fetch that moves origin/main does not.
func TestSymbolicRefRetarget(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	r := f.open()
	a := snap(t, r)
	if a.Refs["refs/remotes/origin/HEAD"] != "-> refs/remotes/origin/main" {
		t.Fatalf("origin/HEAD recorded as %q", a.Refs["refs/remotes/origin/HEAD"])
	}
	run(t, f.host, "symbolic-ref", "refs/remotes/origin/HEAD", "refs/heads/main")
	d := Diff(a, snap(t, r))
	found := false
	for _, c := range d {
		found = found || (c.Kind == KindRef && c.Name == "refs/remotes/origin/HEAD" && c.New == "-> refs/heads/main")
	}
	if !found {
		t.Fatalf("retarget not shown: %v", d)
	}
}

// The fixture is built once per test binary and every test copies it (c0179, "template is built once per package").
func TestTheFixtureIsBuiltOncePerBinary(t *testing.T) {
	t.Parallel()
	for i := 0; i < 3; i++ {
		newFixture(t)
	}
	if n := fixtureBuilds.Load(); n != 1 {
		t.Fatalf("the fixture was built %d times in this binary, want once", n)
	}
}
