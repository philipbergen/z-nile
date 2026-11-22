package host

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// refuses asserts that op fails with every want substring, that no marker was created and that the host's .git did not change.
func refuses(t *testing.T, f *fixture, r *Repo, marker string, op func() error, want ...string) {
	t.Helper()
	before := snap(t, r)
	err := op()
	if err == nil {
		t.Fatal("the write was not refused")
	}
	for _, w := range want {
		if !strings.Contains(err.Error(), w) {
			t.Fatalf("refusal %q lacks %q", err, w)
		}
	}
	if marker != "" {
		if _, e := os.Stat(marker); e == nil {
			t.Fatalf("the program ran: %s exists", marker)
		}
	}
	if d := Diff(before, snap(t, r)); len(d) != 0 {
		t.Fatalf("a refused write changed the host: %v", d)
	}
}

func fetchOp(r *Repo) func() error { return func() error { return r.FetchDefault("origin", "main") } }

// Q1: a local remote.<name>.uploadpack is refused before git runs, and the fetch also passes --upload-pack.
func TestRefusesLocalUploadpack(t *testing.T) {
	f := newFixture(t)
	m := filepath.Join(f.base, "uploadpack-ran")
	run(t, f.host, "config", "remote.origin.uploadpack", "touch "+m+"; git-upload-pack")
	refuses(t, f, f.open(), m, fetchOp(f.open()), "remote.origin.uploadpack", "global git config")
}

// Q1b: with the check bypassed, the command-line --upload-pack still beats the local key.
func TestUploadPackOptionBeatsLocalKey(t *testing.T) {
	f := newFixture(t)
	m := filepath.Join(f.base, "uploadpack-ran")
	run(t, f.host, "config", "remote.origin.uploadpack", "touch "+m+"; git-upload-pack")
	r := f.open()
	r.skipConfigCheck = true
	if err := r.FetchDefault("origin", "main"); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(m); err == nil {
		t.Fatal("remote.origin.uploadpack ran despite --upload-pack on the command line")
	}
}

// Q2: a local core.sshCommand.
func TestRefusesLocalSSHCommand(t *testing.T) {
	f := newFixture(t)
	m := filepath.Join(f.base, "ssh-ran")
	run(t, f.host, "remote", "add", "sshr", "ssh://example.invalid/x.git")
	run(t, f.host, "config", "core.sshCommand", "touch "+m+"; false")
	r := f.open()
	refuses(t, f, r, m, func() error { return r.FetchDefault("sshr", "main") }, "core.sshcommand", ".git/config")
}

// Q3: a local filter driver selected by a .gitattributes in fetched content.
func TestRefusesLocalSmudgeDriver(t *testing.T) {
	f := newFixture(t)
	m := filepath.Join(f.base, "smudge-ran")
	os.WriteFile(filepath.Join(f.seed, ".gitattributes"), []byte("* filter=evil\n"), 0o644)
	run(t, f.seed, "add", ".gitattributes")
	run(t, f.seed, "commit", "-q", "-m", "attr")
	run(t, f.seed, "push", "-q", "origin", "main")
	run(t, f.host, "config", "filter.evil.smudge", "sh -c 'touch "+m+"; cat'")
	r := f.open()
	refuses(t, f, r, m, func() error {
		return r.FetchAndWorktree("origin", "main", branch, filepath.Join(f.host, ".worktree", "R0001"))
	}, "filter.evil.smudge")
}

// Q4 and (c): a filter driver from the user's global config (as git-lfs installs it), selected by fetched content, is
// refused at worktree creation, naming the driver and the path; nothing is created.
func TestRefusesFilterAttribute(t *testing.T) {
	f := newFixture(t)
	m := filepath.Join(f.base, "gsmudge-ran")
	home := realTemp(t)
	os.WriteFile(filepath.Join(home, ".gitconfig"), []byte("[filter \"lfs\"]\n\tsmudge = sh -c 'touch "+m+"; cat'\n"), 0o644)
	t.Setenv("HOME", home)
	t.Setenv("XDG_CONFIG_HOME", "")
	os.MkdirAll(filepath.Join(f.seed, "sub"), 0o755)
	os.WriteFile(filepath.Join(f.seed, "sub", ".gitattributes"), []byte("*.bin filter=lfs diff=lfs\n"), 0o644)
	run(t, f.seed, "add", "sub/.gitattributes")
	run(t, f.seed, "commit", "-q", "-m", "attr")
	run(t, f.seed, "push", "-q", "origin", "main")
	r := f.open()
	wt := filepath.Join(f.host, ".worktree", "R0001")
	if err := r.FetchDefault("origin", "main"); err != nil {
		t.Fatal(err)
	}
	refuses(t, f, r, m, func() error { return r.AddWorktree(wt, branch, "refs/remotes/origin/main") }, `"lfs"`, "sub/.gitattributes")
	if _, err := os.Stat(wt); err == nil {
		t.Fatal("the worktree was created")
	}
}

// (c): attributes that name no filter are fine, and info/attributes is read too.
func TestAttributesWithoutFilterPass(t *testing.T) {
	f := newFixture(t)
	os.WriteFile(filepath.Join(f.seed, ".gitattributes"), []byte("* text=auto\n*.png binary\n# filter=notreally\n"), 0o644)
	run(t, f.seed, "add", ".gitattributes")
	run(t, f.seed, "commit", "-q", "-m", "attr")
	run(t, f.seed, "push", "-q", "origin", "main")
	r := f.open()
	if err := r.FetchAndWorktree("origin", "main", branch, filepath.Join(f.host, ".worktree", "R0001")); err != nil {
		t.Fatalf("harmless attributes refused: %v", err)
	}
	run(t, f.host, "worktree", "remove", "--force", filepath.Join(f.host, ".worktree", "R0001"))
	run(t, f.host, "branch", "-D", branch)
	os.WriteFile(filepath.Join(f.host, ".git", "info", "attributes"), []byte("*.x filter=local\n"), 0o644)
	mustErr(t, r.AddWorktree(filepath.Join(f.host, ".worktree", "R0002"), "zn/b", "refs/remotes/origin/main"), "info/attributes")
}

// Q5: include.path (config pulled from a tracked file) and includeIf are refused.
func TestRefusesLocalInclude(t *testing.T) {
	f := newFixture(t)
	m := filepath.Join(f.base, "include-ran")
	os.WriteFile(filepath.Join(f.seed, "zn.cfg"), []byte("[remote \"origin\"]\n\tuploadpack = touch "+m+"; git-upload-pack\n"), 0o644)
	run(t, f.seed, "add", "zn.cfg")
	run(t, f.seed, "commit", "-q", "-m", "cfg")
	run(t, f.seed, "push", "-q", "origin", "main")
	run(t, f.host, "pull", "-q", "--ff-only", "origin", "main")
	run(t, f.host, "config", "include.path", "../zn.cfg")
	r := f.open()
	refuses(t, f, r, m, fetchOp(r), "include.path", "global git config")
	run(t, f.host, "config", "--unset", "include.path")
	run(t, f.host, "config", "includeIf.gitdir:/x/.path", "../zn.cfg")
	refuses(t, f, r, m, fetchOp(r), "includeif")
}

// A remote whose URL names a transport helper is refused.
func TestRefusesExtRemote(t *testing.T) {
	f := newFixture(t)
	m := filepath.Join(f.base, "ext-ran")
	run(t, f.host, "remote", "add", "evil", "ext::sh -c 'touch "+m+"'")
	r := f.open()
	refuses(t, f, r, m, func() error { return r.FetchDefault("evil", "main") }, "remote.evil.url", "transport")
}

func TestURLAllowed(t *testing.T) {
	for _, u := range []string{"https://github.com/o/r.git", "ssh://git@github.com/o/r", "git@github.com:o/r.git", "/abs/path/r.git", "file:///abs/r.git", "host:path"} {
		if err := urlAllowed(u); err != nil {
			t.Errorf("%q refused: %v", u, err)
		}
	}
	for _, u := range []string{"ext::sh -c x", "fd::3", "foo::bar", "http://x/r", "git://x/r", "ftp://x/r", "../rel", "rel/path", "", "-oProxyCommand=x", "ssh://-oProxyCommand=x/r", "https:// x"} {
		if err := urlAllowed(u); err == nil {
			t.Errorf("%q allowed", u)
		}
	}
}

// A normal clone's config (origin, a fork, a branch) passes the allowlist; the fixture's own would otherwise never deliver.
func TestNormalConfigPasses(t *testing.T) {
	f := newFixture(t)
	for _, kv := range [][2]string{{"user.name", "x"}, {"user.email", "x@y"}, {"pull.rebase", "true"}, {"push.autoSetupRemote", "true"}, {"init.defaultBranch", "main"},
		{"branch.main.rebase", "true"}, {"branch.main.description", "d"}, {"remote.fork.pushurl", "git@github.com:o/r.git"}, {"remote.fork.gh-resolved", "base"},
		{"core.autocrlf", "input"}, {"core.eol", "lf"}, {"core.symlinks", "true"}, {"core.untrackedCache", "true"}, {"submodule.s.url", "https://x/s"}, {"submodule.s.active", "true"}} {
		run(t, f.host, "config", kv[0], kv[1])
	}
	if err := f.open().checkLocalConfig(); err != nil {
		t.Fatalf("a normal config was refused: %v", err)
	}
}

// With extensions.worktreeConfig on, the per-worktree config is held to the same list.
func TestPerWorktreeConfigIsChecked(t *testing.T) {
	f := newFixture(t)
	run(t, f.host, "config", "core.repositoryformatversion", "1")
	run(t, f.host, "config", "extensions.worktreeConfig", "true")
	r := f.open()
	run(t, f.host, "config", "--worktree", "user.name", "ok")
	if err := r.checkLocalConfig(); err != nil {
		t.Fatalf("an allowed per-worktree key was refused: %v", err)
	}
	m := filepath.Join(f.base, "wt-ssh-ran")
	run(t, f.host, "config", "--worktree", "core.sshCommand", "touch "+m)
	err := r.checkLocalConfig()
	mustErr(t, err, "core.sshcommand")
	mustErr(t, err, "config.worktree")
	refuses(t, f, r, m, fetchOp(r), "core.sshcommand")
}

// N1: a refused Open leaves no folder anywhere, the outside repository's working tree included; a hooks folder must be under <root>/.cache.
func treeList(t *testing.T, dir string) string {
	t.Helper()
	var out []string
	filepath.WalkDir(dir, func(p string, d os.DirEntry, err error) error {
		if err == nil {
			rel, _ := filepath.Rel(dir, p)
			if rel == ".git" && d.IsDir() {
				return filepath.SkipDir
			}
			out = append(out, rel)
		}
		return nil
	})
	return strings.Join(out, "\n")
}

func TestRefusedOpenCreatesNothing(t *testing.T) {
	f := newFixture(t)
	sub := filepath.Join(f.host, "sub")
	inner := filepath.Join(sub, "x")
	os.MkdirAll(inner, 0o755)
	before := treeList(t, f.host)
	gitBefore := snap(t, mustOpen(t, f.host, f.host))
	_, err := f.openAt(sub, inner)
	mustErr(t, err, "allowed root")
	if after := treeList(t, f.host); after != before {
		t.Fatalf("a refused Open changed the outside working tree:\n%s\n--\n%s", before, after)
	}
	if d := Diff(gitBefore, snap(t, mustOpen(t, f.host, f.host))); len(d) != 0 {
		t.Fatalf("outside .git changed: %v", d)
	}
}

func TestHooksFolderMustBeUnderCache(t *testing.T) {
	f := newFixture(t)
	for _, h := range []string{filepath.Join(f.host, ".git", "nohooks"), filepath.Join(f.host, "hooks"), filepath.Join(f.host, ".cache"), filepath.Join(f.host, ".cachex", "h")} {
		_, err := Open(f.host, f.host, h)
		mustErr(t, err, "hooks folder")
		if _, e := os.Stat(h); e == nil {
			t.Fatalf("%s was created", h)
		}
	}
	if _, err := Open(f.host, f.host, filepath.Join(f.host, ".cache", "a", "b")); err != nil {
		t.Fatal(err)
	}
	if _, e := os.Stat(filepath.Join(f.host, ".cache", "a")); e == nil {
		t.Fatal("Open created the hooks folder")
	}
}

// N2/Q7: core.worktree pointing elsewhere: only the top-level check stops it.
func TestOpenRefusesCoreWorktreeElsewhere(t *testing.T) {
	f := newFixture(t)
	elsewhere := realTemp(t)
	run(t, f.host, "config", "core.worktree", elsewhere)
	_, err := Open(f.host, f.host, f.hooks())
	mustErr(t, err, "top level")
}

// N2/Q9: a crafted gitfile inside the root whose git directory is outside and whose commondir is the host's .git:
// only the git-directory check stops it.
func TestOpenRefusesCraftedGitfile(t *testing.T) {
	f := newFixture(t)
	gd := filepath.Join(realTemp(t), "gd")
	os.MkdirAll(gd, 0o755)
	os.WriteFile(filepath.Join(gd, "commondir"), []byte(filepath.Join(f.host, ".git")+"\n"), 0o644)
	os.WriteFile(filepath.Join(gd, "HEAD"), []byte("ref: refs/heads/main\n"), 0o644)
	wt := filepath.Join(f.host, "crafted")
	os.MkdirAll(wt, 0o755)
	os.WriteFile(filepath.Join(gd, "gitdir"), []byte(filepath.Join(wt, ".git")+"\n"), 0o644)
	os.WriteFile(filepath.Join(wt, ".git"), []byte("gitdir: "+gd+"\n"), 0o644)
	_, err := Open(f.host, wt, f.hooks())
	mustErr(t, err, "git directory")
}

// Low: which paths are object payload.
func TestIsPayload(t *testing.T) {
	sha1 := strings.Repeat("a", 38)
	sha256 := strings.Repeat("b", 64)
	for rel, want := range map[string]bool{
		"objects/ab/" + sha1:                      true,
		"objects/pack/pack-1f.pack":               true,
		"objects/pack/pack-1f.idx":                true,
		"objects/pack/pack-1f.rev":                true,
		"objects/pack/pack-1f.bitmap":             true,
		"objects/pack/pack-1f.mtimes":             true,
		"objects/pack/pack-1f.keep":               false,
		"objects/pack/multi-pack-index":           false,
		"objects/info/alternates":                 false,
		"objects/info/commit-graph":               false,
		"objects/ab/short":                        false,
		"modules/sub/objects/ab/" + sha1:          true,
		"modules/sub/objects/pack/pack-1f.pack":   true,
		"modules/sub/objects/info/alternates":     false,
		"modules/sub/HEAD":                        false,
		"modules/objects/HEAD":                    false, // a submodule named objects
		"modules/objects/config":                  false,
		"modules/objects/objects/ab/" + sha1:      true,
		"modules/objects/objects/info/alternates": false,
		"modules/a/b/objects/ab/" + sha1:          true,
		"lfs/objects/ab/cd/" + sha256:             true,
		"lfs/objects/ab/cd/short":                 false,
		"lfs/tmp/x":                               false,
		"hooks/objects/ab/" + sha1:                false,
		"worktrees/x/objects/ab/" + sha1:          false,
	} {
		if got := isPayload(rel, false); got != want {
			t.Errorf("isPayload(%q) = %v, want %v", rel, got, want)
		}
	}
}

// Low: a lock file is a change (a stale lock zn left blocks the owner's git), and one that vanishes mid-walk is skipped.
func TestLockFilesAreChanges(t *testing.T) {
	f := newFixture(t)
	r := f.open()
	a := snap(t, r)
	os.WriteFile(filepath.Join(f.host, ".git", "refs", "heads", "main.lock"), []byte("x"), 0o644)
	b := snap(t, r)
	c := fileChange(t, a, b, "refs/heads/main.lock")
	if c.HadOld || !c.HasNew {
		t.Fatalf("lock %+v", c)
	}
	if bad := Allowed([]Change{c}, delivery("R0001")); len(bad) != 1 {
		t.Fatal("Allowed let a stale lock through")
	}
	walkBarrier = func(rel string) {
		if rel == "refs/heads/main.lock" {
			os.Remove(filepath.Join(f.host, ".git", rel))
		}
	}
	defer func() { walkBarrier = nil }()
	s, err := r.Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := s.Files["refs/heads/main.lock"]; ok {
		t.Fatal("a lock that vanished was recorded")
	}
}
