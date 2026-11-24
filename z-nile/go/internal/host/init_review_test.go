package host

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"znile/internal/lunepin"
)

const registryTOML = "retired = []\n[[project]]\nname = \"mine\"\nroot = \"mine/.tracker\"\n"

// globalConfig appends to the test's own global git config (the one zn's writes honour).
func (f *initFixture) globalConfig(t *testing.T, text string) {
	t.Helper()
	p := filepath.Join(f.home, ".gitconfig")
	if err := os.WriteFile(p, []byte(readText(t, p)+text), 0o644); err != nil {
		t.Fatal(err)
	}
}

// seedTracker puts history on branch in the (bare) tracker: files maps path to content.
func (f *initFixture) seedTracker(t *testing.T, branch string, files map[string]string) {
	t.Helper()
	seed := filepath.Join(f.base, "tracker-seed")
	os.MkdirAll(seed, 0o755)
	run(t, seed, "init", "-q", "-b", branch)
	for p, c := range files {
		os.MkdirAll(filepath.Dir(filepath.Join(seed, p)), 0o755)
		os.WriteFile(filepath.Join(seed, p), []byte(c), 0o644)
	}
	run(t, seed, "add", "-A")
	run(t, seed, "commit", "-q", "-m", "seed")
	run(t, seed, "push", "-q", f.tracker, branch)
}

// script writes an executable shell script that records its name and working folder in marker, then runs rest.
func script(t *testing.T, dir, name, marker, rest string) string {
	t.Helper()
	os.MkdirAll(dir, 0o755)
	p := filepath.Join(dir, name)
	body := "#!/bin/sh\necho \"" + name + " $(pwd)\" >> \"" + marker + "\"\n" + rest + "\n"
	if err := os.WriteFile(p, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	return p
}

// Finding 1: a commit that fails (no git identity) must not strand the skeleton files: the next run, with an identity,
// finishes.
func TestInitRecoversFromAFailedCommit(t *testing.T) {
	f := newInitFixture(t)
	good := readText(t, filepath.Join(f.home, ".gitconfig"))
	os.WriteFile(filepath.Join(f.home, ".gitconfig"), []byte("[user]\n\tuseConfigOnly = true\n"), 0o644)
	if _, err := Init(f.opts()); err == nil || !strings.Contains(err.Error(), "user.") {
		t.Fatalf("a commit with no identity must fail naming what git needs, got %v", err)
	}
	os.WriteFile(filepath.Join(f.home, ".gitconfig"), []byte(good), 0o644)
	steps := mustInit(t, f.opts())
	if !strings.Contains(joined(steps), "pushed main") {
		t.Errorf("the second run did not finish: %q", steps)
	}
	if n := run(t, f.tracker, "rev-list", "--count", "main"); n != "1" {
		t.Errorf("%s commits", n)
	}
	// a skeleton file with other content is never overwritten or swallowed
	g := newInitFixture(t)
	run(t, g.base, "clone", "-q", g.tracker, filepath.Join(g.host, ".tracker"))
	os.WriteFile(filepath.Join(g.host, ".tracker", "README.md"), []byte("not zn's\n"), 0o644)
	g.refusesAfterClone(t, "README.md")
}

// refusesAfterClone: init fails naming file, and leaves that file as it was.
func (f *initFixture) refusesAfterClone(t *testing.T, file string) {
	t.Helper()
	p := filepath.Join(f.host, ".tracker", file)
	before := readText(t, p)
	_, err := Init(f.opts())
	if err == nil || !strings.Contains(err.Error(), file) {
		t.Fatalf("want a refusal naming %s, got %v", file, err)
	}
	if readText(t, p) != before {
		t.Errorf("%s was changed", file)
	}
	if run(t, f.tracker, "for-each-ref") != "" {
		t.Error("something was pushed")
	}
}

// Finding 2: a clone cut short (no refs) of a tracker that has history is never committed onto; of an empty tracker it
// is completed.
func TestInitHalfMadeClone(t *testing.T) {
	half := func(f *initFixture) string {
		d := filepath.Join(f.host, ".tracker")
		os.MkdirAll(d, 0o755)
		run(t, d, "init", "-q", "-b", "main")
		run(t, d, "remote", "add", "origin", f.tracker)
		return d
	}
	t.Run("of an empty tracker", func(t *testing.T) {
		f := newInitFixture(t)
		half(f)
		steps := mustInit(t, f.opts())
		if !strings.Contains(joined(steps), "pushed main") {
			t.Errorf("steps %q", steps)
		}
	})
	t.Run("of a tracker with history", func(t *testing.T) {
		f := newInitFixture(t)
		f.seedTracker(t, "main", map[string]string{"z-nile/projects.toml": registryTOML})
		d := half(f)
		head := run(t, f.tracker, "rev-parse", "main")
		f.refuses(t, f.opts(), "move .tracker away")
		if run(t, f.tracker, "rev-parse", "main") != head {
			t.Error("the tracker moved")
		}
		if _, err := os.Stat(filepath.Join(d, "README.md")); err == nil {
			t.Error("a skeleton was written onto the half-made clone")
		}
	})
}

// Finding 3: the push goes to the repository typed, whatever a pushurl or a global rewrite says; nothing is printed of
// the rewritten address.
func TestInitRefusesRewrittenAddresses(t *testing.T) {
	other := func(f *initFixture) string {
		o := filepath.Join(f.base, "elsewhere.git")
		os.MkdirAll(o, 0o755)
		run(t, o, "init", "-q", "--bare", "-b", "main")
		return o
	}
	t.Run("an existing clone with a pushurl elsewhere", func(t *testing.T) {
		f := newInitFixture(t)
		o := other(f)
		clone := filepath.Join(f.host, ".tracker")
		run(t, f.base, "clone", "-q", f.tracker, clone)
		run(t, clone, "config", "remote.origin.pushurl", o)
		f.refuses(t, f.opts(), "push", "another repository")
		if run(t, o, "for-each-ref") != "" {
			t.Error("pushed to the other repository")
		}
	})
	t.Run("pushInsteadOf in the global config", func(t *testing.T) {
		f := newInitFixture(t)
		o := other(f)
		f.globalConfig(t, "[url \""+o+"\"]\n\tpushInsteadOf = "+f.tracker+"\n")
		f.refuses(t, f.opts(), "push", "rewritten")
		if run(t, o, "for-each-ref") != "" {
			t.Error("pushed to the other repository")
		}
	})
	t.Run("insteadOf in the global config, before the clone", func(t *testing.T) {
		f := newInitFixture(t)
		o := other(f)
		f.globalConfig(t, "[url \""+o+"\"]\n\tinsteadOf = "+f.tracker+"\n")
		f.refuses(t, f.opts(), "tracker address", "rewritten")
	})
	t.Run("an existing clone whose fetch alone is rewritten", func(t *testing.T) {
		f := newInitFixture(t)
		o := other(f)
		run(t, f.base, "clone", "-q", f.tracker, filepath.Join(f.host, ".tracker"))
		f.globalConfig(t, "[url \""+o+"\"]\n\tinsteadOf = "+f.tracker+"\n[url \""+f.tracker+"\"]\n\tpushInsteadOf = "+o+"\n")
		f.refuses(t, f.opts(), "fetch", "another repository")
	})
	t.Run("a rewrite that names the same repository is fine", func(t *testing.T) {
		f := newInitFixture(t)
		f.globalConfig(t, "[url \"file://"+f.tracker+"\"]\n\tinsteadOf = "+f.tracker+"\n")
		mustInit(t, f.opts())
	})
}

// Finding 4: the remote decides whether the tracker has history, and a tracker with history is never given a second
// root branch or called set up without a registry.
func TestInitTrackersWithHistory(t *testing.T) {
	t.Run("history only on trunk", func(t *testing.T) {
		f := newInitFixture(t)
		f.seedTracker(t, "trunk", map[string]string{"z-nile/projects.toml": registryTOML})
		f.refuses(t, f.opts(), "no `main`")
		if strings.Contains(run(t, f.tracker, "for-each-ref"), "refs/heads/main") {
			t.Error("a second root branch was pushed")
		}
	})
	t.Run("history on main with no registry", func(t *testing.T) {
		f := newInitFixture(t)
		f.seedTracker(t, "main", map[string]string{"README.md": "x\n"})
		f.refuses(t, f.opts(), "z-nile/projects.toml", "not a z-nile tracker")
	})
	t.Run("an existing clone with no registry", func(t *testing.T) {
		f := newInitFixture(t)
		f.seedTracker(t, "main", map[string]string{"README.md": "x\n"})
		run(t, f.base, "clone", "-q", f.tracker, filepath.Join(f.host, ".tracker"))
		f.refuses(t, f.opts(), "not a z-nile tracker")
	})
	t.Run("a local branch the remote lacks", func(t *testing.T) {
		f := newInitFixture(t)
		clone := filepath.Join(f.host, ".tracker")
		run(t, f.base, "clone", "-q", f.tracker, clone)
		run(t, clone, "checkout", "-q", "-b", "side")
		commit(t, clone, "x")
		f.refuses(t, f.opts(), "side")
	})
	t.Run("a bare tracker whose HEAD is another branch gets main", func(t *testing.T) {
		f := newInitFixture(t)
		run(t, f.tracker, "symbolic-ref", "HEAD", "refs/heads/trunk")
		mustInit(t, f.opts())
		if got := run(t, filepath.Join(f.host, ".tracker"), "symbolic-ref", "HEAD"); got != "refs/heads/main" {
			t.Errorf("HEAD is %s", got)
		}
		if !strings.Contains(run(t, f.tracker, "for-each-ref"), "refs/heads/main") {
			t.Error("main was not pushed")
		}
	})
}

// Finding 5: the project name is in the engine's grammar, --project overrides it and is held to the same grammar.
func TestInitProjectOption(t *testing.T) {
	f := newInitFixture(t)
	o := f.opts()
	o.Project = "mine"
	mustInit(t, o)
	if !strings.Contains(trackerFiles(t, f.tracker), "mine/.tracker/issues/.gitkeep") || !strings.Contains(run(t, f.tracker, "show", "main:z-nile/projects.toml"), `name = "mine"`) {
		t.Errorf("the project is not mine: %s", trackerFiles(t, f.tracker))
	}
	for _, bad := range []string{"Bad Name", "z-nile", "1abc", "a--b"} {
		g := newInitFixture(t)
		o := g.opts()
		o.Project = bad
		g.refuses(t, o, "--project")
	}
}

// Finding 6: lines that count as present must hide something, and git is asked.
func TestInitVerifiesWhatIsIgnored(t *testing.T) {
	t.Run("a later negation", func(t *testing.T) {
		f := newInitFixture(t)
		p := filepath.Join(f.host, ".git", "info", "exclude")
		os.WriteFile(p, []byte(readText(t, p)+".tracker/\n!.tracker/\n"), 0o644)
		_, err := Init(f.opts())
		if err == nil || !strings.Contains(err.Error(), "does not ignore .tracker/") {
			t.Fatalf("got %v", err)
		}
	})
	t.Run("a tracked .gitignore negation beats info/exclude", func(t *testing.T) {
		f := newInitFixture(t)
		os.WriteFile(filepath.Join(f.host, ".gitignore"), []byte("!.cache/\n"), 0o644)
		_, err := Init(f.opts())
		if err == nil || !strings.Contains(err.Error(), "does not ignore .cache/") {
			t.Fatalf("got %v", err)
		}
	})
	t.Run("a leading space or a comment is not the line", func(t *testing.T) {
		f := newInitFixture(t)
		p := filepath.Join(f.host, ".git", "info", "exclude")
		os.WriteFile(p, []byte(readText(t, p)+" .tracker/\n#.worktree/\n"), 0o644)
		mustInit(t, f.opts())
		ex := readText(t, p)
		for _, l := range []string{".tracker/", ".worktree/", ".cache/"} {
			if !strings.Contains(ex, "\n"+l+"\n") {
				t.Errorf("exclude lacks a real %q line:\n%s", l, ex)
			}
		}
	})
}

// Finding 7: clone.defaultRemoteName in the user's config changes nothing.
func TestInitIgnoresDefaultRemoteName(t *testing.T) {
	f := newInitFixture(t)
	f.globalConfig(t, "[clone]\n\tdefaultRemoteName = upstream\n")
	mustInit(t, f.opts())
	if got := run(t, filepath.Join(f.host, ".tracker"), "remote"); got != "origin" {
		t.Errorf("remotes %q", got)
	}
	if steps := mustInit(t, f.opts()); len(steps) != 0 {
		t.Errorf("the second run took steps: %q", steps)
	}
}

// Finding 8: the ignore file is replaced whole, with its mode, and no temp file is left.
func TestInitWritesTheIgnoreFileWhole(t *testing.T) {
	f := newInitFixture(t)
	p := filepath.Join(f.host, ".git", "info", "exclude")
	if err := os.Chmod(p, 0o640); err != nil {
		t.Fatal(err)
	}
	mustInit(t, f.opts())
	if st, _ := os.Stat(p); st.Mode().Perm() != 0o640 {
		t.Errorf("mode %v", st.Mode().Perm())
	}
	ents, _ := os.ReadDir(filepath.Dir(p))
	for _, e := range ents {
		if strings.HasPrefix(e.Name(), ".zn-init") {
			t.Errorf("temp file %s left", e.Name())
		}
	}
}

// No hook of the user's, set through their global core.hooksPath, runs in the tracker clone, commit or push.
func TestInitRunsNoGlobalHooks(t *testing.T) {
	for _, history := range []bool{false, true} {
		f := newInitFixture(t)
		marker := filepath.Join(f.base, "marker")
		hooks := filepath.Join(f.base, "hooks")
		for _, h := range []string{"pre-commit", "commit-msg", "post-commit", "pre-push", "post-checkout", "post-merge", "reference-transaction", "prepare-commit-msg"} {
			script(t, hooks, h, marker, "")
		}
		f.globalConfig(t, "[core]\n\thooksPath = "+hooks+"\n")
		if history {
			f.seedTracker(t, "main", map[string]string{"z-nile/projects.toml": registryTOML})
			os.Remove(marker) // the seeding pushes ran the hooks of the seed repository
		}
		mustInit(t, f.opts())
		b, _ := os.ReadFile(marker)
		for _, line := range strings.Split(string(b), "\n") {
			if strings.Contains(line, "/.tracker") || strings.Contains(line, filepath.Join(f.host)) {
				t.Errorf("history=%v: a hook ran in the tracker clone: %s", history, line)
			}
		}
	}
	// control: the hooks do fire for a plain git commit under that config, so the assertion above can fail
	c := newInitFixture(t)
	marker := filepath.Join(c.base, "marker")
	hooks := filepath.Join(c.base, "hooks")
	script(t, hooks, "post-commit", marker, "")
	c.globalConfig(t, "[core]\n\thooksPath = "+hooks+"\n")
	cmd := exec.Command("git", "-C", c.host, "commit", "-q", "--allow-empty", "-m", "x")
	cmd.Env = append(os.Environ(), "HOME="+c.home, "GIT_CONFIG_NOSYSTEM=1")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("%v %s", err, out)
	}
	if _, err := os.Stat(marker); err != nil {
		t.Fatal("control: the fixture hook does not run, so the test proves nothing")
	}
}

// The clone, the listing and the push name git's own upload-pack and receive-pack, so a remote.origin.uploadpack or
// receivepack in the user's global config runs nothing.
func TestInitNamesGitsOwnPackPrograms(t *testing.T) {
	for _, history := range []bool{false, true} {
		f := newInitFixture(t)
		marker := filepath.Join(f.base, "marker")
		up := script(t, filepath.Join(f.base, "bin"), "up", marker, `exec git-upload-pack "$@"`)
		rp := script(t, filepath.Join(f.base, "bin"), "rp", marker, `exec git-receive-pack "$@"`)
		if history {
			f.seedTracker(t, "main", map[string]string{"z-nile/projects.toml": registryTOML})
		}
		f.globalConfig(t, "[remote \"origin\"]\n\tuploadpack = "+up+"\n\treceivepack = "+rp+"\n")
		mustInit(t, f.opts())
		if b, err := os.ReadFile(marker); err == nil {
			t.Errorf("history=%v: a program from the config ran:\n%s", history, b)
		}
	}
}

// A tracker with history is attacker-controlled content: a .gitattributes that selects a filter driver the user's
// config defines must not run it, and symlinks and submodules inside it write nothing.
func TestInitHostileTracker(t *testing.T) {
	t.Run("a filter driver", func(t *testing.T) {
		f := newInitFixture(t)
		marker := filepath.Join(f.base, "marker")
		smudge := script(t, filepath.Join(f.base, "bin"), "smudge", marker, "cat")
		f.globalConfig(t, "[filter \"evil\"]\n\tsmudge = "+smudge+"\n\trequired = false\n")
		f.seedTracker(t, "main", map[string]string{"z-nile/projects.toml": registryTOML, ".gitattributes": "* filter=evil\n"})
		f.refuses(t, f.opts(), "filter", "evil")
		if _, err := os.Stat(marker); err == nil {
			t.Error("the filter ran")
		}
		// control: a plain clone under the same config does run it
		cmd := exec.Command("git", "clone", "-q", f.tracker, filepath.Join(f.base, "plain"))
		cmd.Env = append(os.Environ(), "HOME="+f.home, "GIT_CONFIG_NOSYSTEM=1")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("%v %s", err, out)
		}
		if _, err := os.Stat(marker); err != nil {
			t.Fatal("control: the filter does not run in a plain clone, so the test proves nothing")
		}
	})
	t.Run("a symlink and a submodule", func(t *testing.T) {
		f := newInitFixture(t)
		outside := filepath.Join(f.base, "outside")
		os.WriteFile(outside, []byte("keep\n"), 0o644)
		f.globalConfig(t, "[submodule]\n\trecurse = true\n")
		seed := filepath.Join(f.base, "tracker-seed")
		os.MkdirAll(seed, 0o755)
		run(t, seed, "init", "-q", "-b", "main")
		os.MkdirAll(filepath.Join(seed, "z-nile"), 0o755)
		os.WriteFile(filepath.Join(seed, "z-nile", "projects.toml"), []byte(registryTOML), 0o644)
		os.Symlink(outside, filepath.Join(seed, "README.md"))
		os.WriteFile(filepath.Join(seed, ".gitmodules"), []byte("[submodule \"sub\"]\n\tpath = sub\n\turl = "+f.upstream+"\n"), 0o644)
		run(t, seed, "add", "-A")
		run(t, seed, "update-index", "--add", "--cacheinfo", "160000,"+run(t, f.seed, "rev-parse", "HEAD")+",sub")
		run(t, seed, "commit", "-q", "-m", "seed")
		run(t, seed, "push", "-q", f.tracker, "main")
		steps := mustInit(t, f.opts())
		if strings.Contains(joined(steps), "initialised") {
			t.Errorf("steps %q", steps)
		}
		if readText(t, outside) != "keep\n" {
			t.Error("a file outside changed")
		}
		if _, err := os.Stat(filepath.Join(f.host, ".tracker", ".git", "modules")); err == nil {
			t.Error("a submodule was fetched")
		}
		if ents, _ := os.ReadDir(filepath.Join(f.host, ".tracker", "sub")); len(ents) != 0 {
			t.Errorf("the submodule was populated: %v", ents)
		}
	})
}

// The skeleton, whole.
func TestInitSkeletonExactly(t *testing.T) {
	f := newInitFixture(t)
	run(t, f.tracker, "symbolic-ref", "HEAD", "refs/heads/trunk")
	mustInit(t, f.opts())
	show := func(p string) string { return run(t, f.tracker, "show", "main:"+p) }
	if got, want := show("z-nile/projects.toml"), strings.TrimSpace(`# The projects this tracker holds. Written by `+"`zn init`"+`; read by z-nile's engine.
retired = []

[[project]]
name = "upstream"
root = "upstream/.tracker"`); got != want {
		t.Errorf("projects.toml:\n%s\nwant:\n%s", got, want)
	}
	if got, want := show(".gitignore"), "# machine-local state zn keeps in this checkout\n.cache/\nprompt.md\n.worktree/"; got != want {
		t.Errorf(".gitignore:\n%s", got)
	}
	if got, want := show("z-nile/next"), "issue 1 start\nraft 1 start"; got != want {
		t.Errorf("next:\n%s", got)
	}
	wantReadme := "# upstream tracker\n\nThis repository is the public work record of the z-nile pipeline for the host project `upstream`: its tickets, designs, reviews, rafts, guesses and lessons. It is written by tooling (`zn`), not by hand, and everything committed to it is public.\n\n## Layout\n\n- `z-nile/projects.toml` lists the projects this tracker holds.\n- `upstream/.tracker/issues/` holds one folder per ticket.\n- `upstream/.tracker/rafts/` holds the rafts, which group tickets into one delivery.\n\nThe host project's own code is not here: it lives in the host repository and reaches it through pull requests."
	if got := show("README.md"); got != wantReadme {
		t.Errorf("README:\n%s", got)
	}
	if got := run(t, f.tracker, "ls-tree", "-r", "--name-only", "main"); got != ".gitignore\nREADME.md\nupstream/.tracker/issues/.gitkeep\nupstream/.tracker/rafts/.gitkeep\nz-nile/next\nz-nile/projects.toml" {
		t.Errorf("files:\n%s", got)
	}
}

// The remaining refusals and modes the review named.
func TestInitMoreRefusalsAndModes(t *testing.T) {
	t.Run("the tracker is a host remote's push address", func(t *testing.T) {
		f := newInitFixture(t)
		other := filepath.Join(f.base, "unrelated.git")
		os.MkdirAll(other, 0o755)
		run(t, other, "init", "-q", "--bare")
		run(t, f.host, "remote", "add", "extra", other)
		run(t, f.host, "config", "remote.extra.pushurl", f.tracker)
		f.refuses(t, f.opts(), "tracker", "remote")
	})
	t.Run(".git/info is a link", func(t *testing.T) {
		f := newInitFixture(t)
		real := filepath.Join(f.base, "realinfo")
		os.Rename(filepath.Join(f.host, ".git", "info"), real)
		os.Symlink(real, filepath.Join(f.host, ".git", "info"))
		f.refuses(t, f.opts(), ".git/info", "link")
	})
	t.Run("info/exclude is a folder", func(t *testing.T) {
		f := newInitFixture(t)
		p := filepath.Join(f.host, ".git", "info", "exclude")
		os.Remove(p)
		os.MkdirAll(p, 0o755)
		f.refuses(t, f.opts(), "exclude", "not a plain file")
	})
	t.Run("a host with no fork goes on and says so", func(t *testing.T) {
		f := newInitFixture(t)
		run(t, f.host, "remote", "remove", "fork")
		steps := mustInit(t, f.opts())
		if !strings.Contains(joined(steps), "no fork of yours yet") {
			t.Errorf("steps %q", steps)
		}
	})
	t.Run("the flag on one run and off the next, and the reverse", func(t *testing.T) {
		for _, first := range []bool{true, false} {
			f := newInitFixture(t)
			o := f.opts()
			o.Gitignore = first
			mustInit(t, o)
			o.Gitignore = !first
			steps := mustInit(t, o)
			if len(steps) != 1 || !strings.Contains(steps[0], "added") {
				t.Errorf("first=%v: the other file still needs its lines, and only that: %q", first, steps)
			}
			o.Gitignore = first
			if steps := mustInit(t, o); len(steps) != 0 {
				t.Errorf("first=%v: a third run took steps: %q", first, steps)
			}
		}
	})
}

// repoRoot is the repository that holds this module, found by walking up to the engine's registry reader.
func repoRoot(t *testing.T) string {
	t.Helper()
	d, _ := filepath.Abs(".")
	for ; d != filepath.Dir(d); d = filepath.Dir(d) {
		if _, err := os.Stat(filepath.Join(d, "z-nile", "engine", "projects.luau")); err == nil {
			return d
		}
	}
	t.Skip("no engine beside the module")
	return ""
}

// The engine's own registry reader (z-nile/engine/projects.luau) reads the registry init generates, for the names the
// derivation produces. It runs lune on a script under the repository's own .cache and reads the file from a temp
// folder; no network.
func TestInitRegistryIsReadByTheEngine(t *testing.T) {
	root := repoRoot(t)
	sum, err := os.ReadFile(filepath.Join(root, "z-nile", "go", "cmd", "zn", "lune.sum"))
	if err != nil {
		t.Fatal(err)
	}
	lune, ok := lunepin.Find(string(sum), os.Getenv("PATH"), os.Getenv("HOME"))
	if !ok {
		t.Skip("no Lune that matches cmd/zn/lune.sum was found: the test will not run an unverified binary")
	}
	work, err := os.MkdirTemp(filepath.Join(root, ".cache"), "init-registry-")
	if err != nil {
		t.Skipf("no .cache to work in: %v", err)
	}
	defer os.RemoveAll(work)
	script := filepath.Join(work, "read.luau")
	body := "--!strict\nlocal fs = require(\"@lune/fs\")\nlocal process = require(\"@lune/process\")\nlocal projects = require(\"@znile/engine/projects\")\n" +
		"local reg, err = projects.parse(fs.readFile(process.args[1]))\nif not reg then error(err) end\nprint(reg.projects[1].name .. \" \" .. reg.projects[1].root .. \" \" .. reg.projects[1].home)\n"
	if err := os.WriteFile(script, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"omarchy", "p-1password-cli", "a-b-c"} {
		var reg string
		for _, f := range trackerSkeleton(name) {
			if f.name == "z-nile/projects.toml" {
				reg = f.body
			}
		}
		file := filepath.Join(work, name+".toml")
		os.WriteFile(file, []byte(reg), 0o644)
		ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
		cmd := lunepin.Command(ctx, lune, "run", script, file)
		cmd.Dir = root
		out, err := cmd.CombinedOutput()
		cancel()
		if err != nil {
			t.Fatalf("%s: the engine refused the generated registry: %v\n%s", name, err, out)
		}
		if want := name + " " + name + "/.tracker " + name; strings.TrimSpace(string(out)) != want {
			t.Errorf("%s: the engine read %q, want %q", name, out, want)
		}
	}
}
