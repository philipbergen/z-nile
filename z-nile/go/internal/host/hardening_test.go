package host

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func (f *fixture) hooks() string { return filepath.Join(f.host, ".cache", "nohooks") }

func (f *fixture) openAt(root, dir string) (*Repo, error) {
	return Open(root, dir, filepath.Join(root, ".cache", "nohooks"))
}

func mustErr(t *testing.T, err error, want string) {
	t.Helper()
	if err == nil || !strings.Contains(err.Error(), want) {
		t.Fatalf("error %v, want one containing %q", err, want)
	}
}

// F1/P1: a folder inside the root that is not a repository must not let git discovery walk up to a repository outside.
func TestOpenRefusesDiscoveryEscape(t *testing.T) {
	f := newFixture(t)
	outside := mustOpen(t, f.host, f.host)
	before := snap(t, outside)
	sub := filepath.Join(f.host, "sub")
	inner := filepath.Join(sub, "x")
	if err := os.MkdirAll(inner, 0o755); err != nil {
		t.Fatal(err)
	}
	r, err := f.openAt(sub, inner)
	mustErr(t, err, "allowed root")
	if r != nil {
		t.Fatal("a Repo was returned with the error")
	}
	if d := Diff(before, snap(t, outside)); len(d) != 0 {
		t.Fatalf("the outside repository changed: %v", d)
	}
}

// F1/P10: a linked worktree of an outside repository, placed inside the root, resolves to a common dir outside it.
func TestOpenRefusesForeignWorktree(t *testing.T) {
	f := newFixture(t)
	outside := realTemp(t)
	other := filepath.Join(outside, "other")
	if err := os.MkdirAll(other, 0o755); err != nil {
		t.Fatal(err)
	}
	run(t, other, "init", "-q", "-b", "main")
	commit(t, other, "o")
	run(t, other, "remote", "add", "origin", f.upstream)
	root := filepath.Join(f.base, "rootdir")
	if err := os.MkdirAll(root, 0o755); err != nil {
		t.Fatal(err)
	}
	wt := filepath.Join(root, "foreign")
	run(t, other, "worktree", "add", "-q", wt)
	ob := snap(t, mustOpen(t, other, other))
	_, err := f.openAt(root, wt)
	mustErr(t, err, "git directory")
	if d := Diff(ob, snap(t, mustOpen(t, other, other))); len(d) != 0 {
		t.Fatalf("the outside repository changed: %v", d)
	}
}

// F1: a git dir outside the root (a separate git dir), a root that is not the repository's own top, and "/" are refused.
func TestOpenRefusesOddRoots(t *testing.T) {
	f := newFixture(t)
	gitdir := filepath.Join(realTemp(t), "sep.git")
	repo := filepath.Join(f.base, "sep")
	if err := os.MkdirAll(repo, 0o755); err != nil {
		t.Fatal(err)
	}
	run(t, repo, "init", "-q", "--separate-git-dir", gitdir)
	_, err := f.openAt(repo, repo)
	mustErr(t, err, "git directory")
	// the root holds the repository below it, not at it: the common dir must be exactly <root>/.git
	_, err = f.openAt(f.base, f.host)
	mustErr(t, err, "common git directory")
	_, err = Open("/", f.host, f.hooks())
	mustErr(t, err, "root")
	_, err = Open(f.host, f.host, filepath.Join(f.base, "elsewhere"))
	mustErr(t, err, "hooks folder")
}

// F6: a sibling folder whose name starts with the root's name is outside it.
func TestSiblingPrefixIsOutside(t *testing.T) {
	f := newFixture(t)
	sib := f.host + "-x"
	if err := os.MkdirAll(sib, 0o755); err != nil {
		t.Fatal(err)
	}
	run(t, sib, "init", "-q", "-b", "main")
	_, err := f.openAt(f.host, sib)
	mustErr(t, err, "not inside the allowed root")
	r := f.open()
	mustErr(t, r.AddWorktree(filepath.Join(sib, "wt"), "zn/x", "refs/remotes/origin/main"), "not inside the allowed root")
}

func fileChange(t *testing.T, a, b Snapshot, name string) Change {
	t.Helper()
	for _, c := range Diff(a, b) {
		if c.Kind == KindFile && c.Name == name {
			return c
		}
	}
	t.Fatalf("no file change for %s in %v", name, Diff(a, b))
	return Change{}
}

// F2: every kind of write to the git directory shows, except object payloads.
func TestSnapshotSeesEveryFileKind(t *testing.T) {
	f := newFixture(t)
	r := f.open()
	git := filepath.Join(f.host, ".git")
	a := snap(t, r)
	if err := os.WriteFile(filepath.Join(git, "objects", "info", "alternates"), []byte("/elsewhere/objects\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/elsewhere", filepath.Join(git, "evil-link")); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(filepath.Join(git, "hooks", "pre-commit.sample"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(git, "info", "exclude"), []byte("x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(git, "hooks", "x"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(git, "emptydir"), 0o755); err != nil {
		t.Fatal(err)
	}
	// object payloads are skipped; a .keep file next to a pack is not a payload
	os.MkdirAll(filepath.Join(git, "objects", "ab"), 0o755)
	os.WriteFile(filepath.Join(git, "objects", "ab", strings.Repeat("c", 38)), []byte("p"), 0o644)
	os.WriteFile(filepath.Join(git, "objects", "pack", "pack-1.pack"), []byte("p"), 0o644)
	os.WriteFile(filepath.Join(git, "objects", "pack", "pack-1.keep"), []byte("p"), 0o644)
	os.WriteFile(filepath.Join(git, "sample.lock"), []byte("p"), 0o644)
	b := snap(t, r)
	for _, name := range []string{"objects/info/alternates", "evil-link", "hooks/pre-commit.sample", "info/exclude", "hooks/x", "emptydir/", "objects/pack/pack-1.keep", "sample.lock"} {
		c := fileChange(t, a, b, name)
		if name == "evil-link" && !strings.Contains(c.New, "-> /elsewhere") {
			t.Fatalf("symlink recorded as %q", c.New)
		}
	}
	for _, name := range []string{"objects/ab/" + strings.Repeat("c", 38), "objects/pack/pack-1.pack"} {
		if _, ok := b.Files[name]; ok {
			t.Fatalf("%s should be skipped", name)
		}
	}
}

// F2: a symlink is recorded, never followed.
func TestSnapshotDoesNotFollowSymlinks(t *testing.T) {
	f := newFixture(t)
	r := f.open()
	outside := realTemp(t)
	if err := os.WriteFile(filepath.Join(outside, "secret"), []byte("s"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(f.host, ".git", "dirlink")); err != nil {
		t.Fatal(err)
	}
	s := snap(t, r)
	for name := range s.Files {
		if strings.HasPrefix(name, "dirlink/") {
			t.Fatalf("followed a symlink into %s", name)
		}
	}
	if !strings.Contains(s.Files["dirlink"], "-> "+outside) {
		t.Fatalf("dirlink recorded as %q", s.Files["dirlink"])
	}
}

// F3/P4: a configured extra refspec for the source ref does not make the designed fetch update another ref.
func TestFetchIgnoresConfiguredRefspecs(t *testing.T) {
	f := newFixture(t)
	run(t, f.host, "config", "--add", "remote.origin.fetch", "+refs/heads/main:refs/remotes/extra/main")
	run(t, f.host, "config", "--add", "remote.origin.fetch", "+refs/tags/*:refs/tags/*")
	r := f.open()
	before := snap(t, r)
	if err := r.FetchDefault("origin", "main"); err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, c := range Diff(before, snap(t, r)) {
		if c.Kind == KindRef {
			names = append(names, c.Name)
		}
	}
	if strings.Join(names, " ") != "refs/remotes/origin/main" {
		t.Fatalf("ref changes %v, want only origin/main", names)
	}
}

// F3: a force-pushed upstream default branch does not leave the fetch stuck.
func TestFetchSurvivesForcePush(t *testing.T) {
	f := newFixture(t)
	r := f.open()
	if err := r.FetchDefault("origin", "main"); err != nil {
		t.Fatal(err)
	}
	run(t, f.seed, "reset", "-q", "--hard", "HEAD~1")
	commit(t, f.seed, "c")
	run(t, f.seed, "push", "-q", "-f", "origin", "main")
	if err := r.FetchDefault("origin", "main"); err != nil {
		t.Fatalf("a non-fast-forward upstream broke the fetch: %v", err)
	}
	if got, want := snap(t, r).Refs["refs/remotes/origin/main"], run(t, f.upstream, "rev-parse", "main"); got != want {
		t.Fatalf("origin/main %s, want %s", got, want)
	}
}

// F3/P2: the user's own fetch.prune and fetch.pruneTags delete nothing in the designed fetch.
func TestFetchDeletesNothingWhenPruneIsConfigured(t *testing.T) {
	f := newFixture(t)
	run(t, f.host, "tag", "localonly")
	run(t, f.host, "update-ref", "refs/remotes/origin/stale", "HEAD")
	run(t, f.host, "config", "fetch.prune", "true")
	run(t, f.host, "config", "fetch.pruneTags", "true")
	r := f.open()
	mustErr(t, r.FetchDefault("origin", "main"), "fetch.prune") // the allowlist refuses it first
	r.skipConfigCheck = true                                    // and with it out of the way the pins still delete nothing
	before := snap(t, r)
	if err := r.FetchDefault("origin", "main"); err != nil {
		t.Fatal(err)
	}
	for _, c := range Diff(before, snap(t, r)) {
		if c.Kind == KindRef && !c.HasNew {
			t.Fatalf("a ref was deleted: %s", c)
		}
	}
	for _, name := range []string{"refs/tags/localonly", "refs/remotes/origin/stale"} {
		if snap(t, r).Refs[name] == "" {
			t.Fatalf("%s is gone", name)
		}
	}
}

// F4: reads ignore the user's global git config, even with a HOME that holds one.
func TestReadsIgnoreGlobalConfig(t *testing.T) {
	f := newFixture(t)
	home := realTemp(t)
	if err := os.WriteFile(filepath.Join(home, ".gitconfig"), []byte("[zz]\n\ttrap = global\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	r := f.open()
	out, err := r.readGit("config", "--list")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(out, "zz.trap") {
		t.Fatal("a read saw the user's global config")
	}
}

// F4: the write path honours the user's global config (a url rewrite makes a fake remote resolve).
func TestWritesHonourGlobalConfig(t *testing.T) {
	f := newFixture(t)
	home := realTemp(t)
	body := "[url \"" + f.upstream + "\"]\n\tinsteadOf = fakescheme:up\n"
	if err := os.WriteFile(filepath.Join(home, ".gitconfig"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", "")
	run(t, f.host, "remote", "add", "fake", "fakescheme:up")
	r := f.open()
	if err := r.FetchDefault("fake", "main"); err != nil {
		t.Fatalf("the global url rewrite was not honoured: %v", err)
	}
	if run(t, f.host, "rev-parse", "refs/remotes/fake/main") != run(t, f.upstream, "rev-parse", "main") {
		t.Fatal("fake/main is not the upstream main")
	}
}

// F4: no hook of the host runs during zn's own git operations; the same hooks do run for a plain git worktree add.
func TestNoHooksRun(t *testing.T) {
	hookBody := func(marker string) string {
		return "#!/bin/sh\necho ran >> \"" + marker + "\"\n"
	}
	install := func(f *fixture, marker string) {
		for _, h := range []string{"post-checkout", "reference-transaction", "post-merge", "pre-auto-gc"} {
			if err := os.WriteFile(filepath.Join(f.host, ".git", "hooks", h), []byte(hookBody(marker)), 0o755); err != nil {
				t.Fatal(err)
			}
		}
	}
	// control: the hooks fire for a plain git call, so the assertion below can fail
	c := newFixture(t)
	cm := filepath.Join(c.base, "control-marker")
	install(c, cm)
	run(t, c.host, "worktree", "add", "-q", "--no-track", "-b", "ctl", filepath.Join(c.host, ".worktree", "C"), "refs/heads/main")
	if _, err := os.Stat(cm); err != nil {
		t.Fatal("control: the fixture hooks do not run, so this test proves nothing")
	}
	f := newFixture(t)
	marker := filepath.Join(f.base, "marker")
	install(f, marker)
	r := f.open()
	if err := r.FetchAndWorktree("origin", "main", branch, filepath.Join(f.host, ".worktree", "R0001")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(marker); err == nil {
		b, _ := os.ReadFile(marker)
		t.Fatalf("a host hook ran: %s", b)
	}
}

// F4: the hooks folder must stay empty, or the write is refused.
func TestHooksFolderMustBeEmpty(t *testing.T) {
	f := newFixture(t)
	r := f.open()
	os.MkdirAll(f.hooks(), 0o755)
	if err := os.WriteFile(filepath.Join(f.hooks(), "post-checkout"), []byte("#!/bin/sh\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	mustErr(t, r.FetchDefault("origin", "main"), "not empty")
}

// F4: the environments come from an allowlist; reads pin the global and system config to nothing, writes do not.
func TestEnvironmentAllowlist(t *testing.T) {
	in := []string{"PATH=/bin", "HOME=/h", "USER=u", "LOGNAME=u", "TMPDIR=/t", "LANG=C", "LC_ALL=C", "SSH_AUTH_SOCK=/s", "XDG_CONFIG_HOME=/x",
		"FOO=bar", "GIT_SSH_COMMAND=evil", "GIT_DIR=/d", "GIT_CONFIG_GLOBAL=/g", "http_proxy=p", "EDITOR=vi"}
	has := func(env []string, kv string) bool {
		for _, e := range env {
			if e == kv {
				return true
			}
		}
		return false
	}
	for _, mode := range []struct {
		name string
		env  []string
	}{{"read", readEnv(in, "/ceil")}, {"write", writeEnv(in, "/ceil")}} {
		for _, keep := range []string{"PATH=/bin", "HOME=/h", "USER=u", "LOGNAME=u", "TMPDIR=/t", "LANG=C", "LC_ALL=C", "SSH_AUTH_SOCK=/s", "XDG_CONFIG_HOME=/x", "GIT_CEILING_DIRECTORIES=/ceil", "GIT_TERMINAL_PROMPT=0"} {
			if !has(mode.env, keep) {
				t.Fatalf("%s env lacks %s", mode.name, keep)
			}
		}
		for _, drop := range []string{"FOO=bar", "GIT_SSH_COMMAND=evil", "GIT_DIR=/d", "GIT_CONFIG_GLOBAL=/g", "http_proxy=p", "EDITOR=vi"} {
			if has(mode.env, drop) {
				t.Fatalf("%s env kept %s", mode.name, drop)
			}
		}
	}
	if !has(readEnv(in, "/c"), "GIT_CONFIG_GLOBAL=/dev/null") || !has(readEnv(in, "/c"), "GIT_CONFIG_SYSTEM=/dev/null") {
		t.Fatal("reads do not pin the global and system config to /dev/null")
	}
	for _, kv := range writeEnv(in, "/c") {
		if strings.HasPrefix(kv, "GIT_CONFIG_GLOBAL=") || strings.HasPrefix(kv, "GIT_CONFIG_SYSTEM=") {
			t.Fatalf("writes pin %s", kv)
		}
	}
}

// F5: a file that vanishes during the walk, and a lock file, do not fail the snapshot.
func TestSnapshotSurvivesVanishingFile(t *testing.T) {
	f := newFixture(t)
	r := f.open()
	victim := filepath.Join(f.host, ".git", "hooks", "pre-commit.sample")
	if _, err := os.Stat(victim); err != nil {
		t.Fatal(err)
	}
	fired := false
	walkBarrier = func(rel string) {
		if rel == "hooks/pre-commit.sample" {
			fired = true
			os.Remove(victim)
		}
	}
	defer func() { walkBarrier = nil }()
	s, err := r.Snapshot()
	if err != nil {
		t.Fatalf("a vanished file failed the snapshot: %v", err)
	}
	if !fired {
		t.Fatal("the barrier never fired, so the test proves nothing")
	}
	if _, ok := s.Files["hooks/pre-commit.sample"]; ok {
		t.Fatal("the vanished file was recorded")
	}
}

// F7: Allowed rejects everything outside the delivery, and the extension point admits what a later step adds.
func TestAllowed(t *testing.T) {
	f := newFixture(t)
	r := f.open()
	before := snap(t, r)
	if err := r.FetchAndWorktree("origin", "main", branch, filepath.Join(f.host, ".worktree", "R0001")); err != nil {
		t.Fatal(err)
	}
	changes := Diff(before, snap(t, r))
	d := delivery("R0001")
	if bad := violations(changes, d); bad != "" {
		t.Fatalf("the real delivery was rejected:\n%s", bad)
	}
	other := d
	other.Branch = "zn/other"
	if violations(changes, other) == "" {
		t.Fatal("a different branch name was allowed")
	}
	extra := []Change{
		{Kind: KindFile, Name: "hooks/x", New: "h", HasNew: true},
		{Kind: KindConfig, Name: "branch." + branch + ".remote", New: "origin", HasNew: true},
		{Kind: KindRef, Name: "refs/tags/v9", New: "abc", HasNew: true},
		{Kind: KindRef, Name: "refs/heads/main", Old: "a", New: "b", HadOld: true, HasNew: true},
		{Kind: KindRef, Name: "refs/heads/" + branch, Old: "a", New: "b", HadOld: true, HasNew: true},
		{Kind: KindRef, Name: "refs/remotes/origin/main", Old: "a", HadOld: true},
		{Kind: KindRef, Name: "refs/remotes/origin/other", New: "a", HasNew: true},
	}
	if got := Allowed(extra, d); len(got) != len(extra) {
		t.Fatalf("Allowed let through %d of %d stray changes", len(extra)-len(got), len(extra))
	}
	d.Extra = func(c Change) bool { return c.Kind == KindRef && c.Name == "refs/remotes/fork/"+branch }
	fork := []Change{{Kind: KindRef, Name: "refs/remotes/fork/" + branch, New: "abc", HasNew: true}}
	if len(Allowed(fork, d)) != 0 || len(Allowed(fork, delivery("R0001"))) != 1 {
		t.Fatal("the Extra extension point does not admit exactly its own entries")
	}
}

// F7: the first delivery into a host with no remote-tracking ref yet, and a fetch run from a linked worktree.
func TestAllowedFirstFetchAndPerWorktreeFetchHead(t *testing.T) {
	f := newFixture(t)
	run(t, f.host, "symbolic-ref", "--delete", "refs/remotes/origin/HEAD") // a host that never fetched the default branch
	run(t, f.host, "update-ref", "-d", "refs/remotes/origin/main")
	r := f.open()
	before := snap(t, r)
	if err := r.FetchAndWorktree("origin", "main", branch, filepath.Join(f.host, ".worktree", "R0001")); err != nil {
		t.Fatal(err)
	}
	if bad := violations(Diff(before, snap(t, r)), delivery("R0001")); bad != "" {
		t.Fatalf("first-time creation of the remote-tracking ref rejected:\n%s", bad)
	}
	// a second raft started from inside the first worktree writes that worktree's own FETCH_HEAD
	r2, err := Open(f.host, filepath.Join(f.host, ".worktree", "R0001"), f.hooks())
	if err != nil {
		t.Fatal(err)
	}
	before = snap(t, r2)
	d := Delivery{Remote: "origin", Default: "main", Branch: "zn/R0002-y", WorktreeName: "R0002"}
	if err := r2.FetchAndWorktree("origin", "main", d.Branch, filepath.Join(f.host, ".worktree", "R0002")); err != nil {
		t.Fatal(err)
	}
	ch := Diff(before, snap(t, r2))
	if bad := violations(ch, d); bad != "" {
		t.Fatalf("a fetch from a worktree rejected:\n%s", bad)
	}
}

// F8: a removed empty-valued key is a removal, and an empty value differs from a bare (implicit true) key.
func TestConfigPresenceAndEmptyValues(t *testing.T) {
	f := newFixture(t)
	r := f.open()
	run(t, f.host, "config", "zz.empty", "")
	a := snap(t, r)
	run(t, f.host, "config", "--unset", "zz.empty")
	var got []Change
	for _, c := range Diff(a, snap(t, r)) {
		if c.Kind == KindConfig {
			got = append(got, c)
		}
	}
	if len(got) != 1 || !got[0].HadOld || got[0].HasNew || got[0].Name != "zz.empty" {
		t.Fatalf("removal of an empty-valued key: %+v", got)
	}
	if !strings.HasPrefix(got[0].String(), "config -zz.empty") {
		t.Fatalf("rendered as %q", got[0].String())
	}
	cfg := filepath.Join(f.host, ".git", "config")
	orig, _ := os.ReadFile(cfg)
	os.WriteFile(cfg, append(orig, []byte("[zz]\n\tflag\n")...), 0o644)
	bare := snap(t, r)
	os.WriteFile(cfg, append(orig, []byte("[zz]\n\tflag =\n")...), 0o644)
	var flag []Change
	for _, c := range Diff(bare, snap(t, r)) {
		if c.Kind == KindConfig {
			flag = append(flag, c)
		}
	}
	if len(flag) != 1 || flag[0].Name != "zz.flag" || !flag[0].HadOld || !flag[0].HasNew {
		t.Fatalf("a bare key and an empty value look equal: %+v", flag)
	}
}
