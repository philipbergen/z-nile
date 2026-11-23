package host

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"strings"
)

// InitOptions is one `zn init <tracker-address>` (f0428 step 3).
type InitOptions struct {
	Root      string    // the host's main checkout: the folder zn init is run in
	Tracker   string    // the address of the user's own tracker repository
	Gitignore bool      // hide .tracker, .worktree and .cache in the host's tracked .gitignore instead of its info/exclude
	Overrides Overrides // --fork and --upstream: overrides only, init asks nothing about remotes
	Project   string    // --project: the project's name in the tracker, when it cannot be taken from the upstream's name
	Lookup    Lookup    // what GitHub says about the host's remotes; injected, this package never reaches the network
}

// zn's three folders in the host, in the order they are listed in an ignore file.
var znFolders = []string{".tracker/", ".worktree/", ".cache/"}

// Init sets zn up in a host repository: it refuses, naming the cause, before it writes anything it could not undo;
// then it clones the tracker to <Root>/.tracker (when missing), initialises an empty tracker, pushes it, and keeps
// .tracker out of the host. Every step checks before it writes, so a second run takes none. It returns the steps it
// took, one line each (and the steps taken so far with an error that stops it midway). The push is the one outward
// act: it goes only to the repository o.Tracker names, which is checked after every rewrite git's config applies to
// the address. The host's own refs, config and tracked files are never written.
func Init(o InitOptions) ([]string, error) {
	var steps []string
	if err := CheckHost(o.Root); err != nil {
		return nil, err
	}
	root, err := resolve(o.Root)
	if err != nil {
		return nil, err
	}
	if err := CheckAddress(o.Tracker); err != nil {
		return nil, fmt.Errorf("host: the tracker address cannot be used: %w", err)
	}
	trackerID, err := ParseRemote(o.Tracker)
	if err != nil {
		return nil, fmt.Errorf("host: the tracker address is not a repository on a host (owner and name): %w", err)
	}
	hostRepo, err := Open(root, root, filepath.Join(root, ".cache", "nohooks"))
	if err != nil {
		return nil, err
	}
	remotes, err := hostRepo.Remotes()
	if err != nil {
		return nil, err
	}
	for _, rm := range remotes {
		if rm.Err == nil && rm.NoIdentity == nil && (trackerID.Same(rm.Fetch) || (!rm.PushDisabled && trackerID.Same(rm.Push))) {
			return nil, fmt.Errorf("host: the tracker address is the address of the host's remote %q: the tracker must be a repository of its own, or zn would push its tickets into the host's project", rm.Name)
		}
	}
	if o.Lookup == nil {
		return nil, errors.New("host: init needs a way to ask GitHub which remote is the fork")
	}
	res, err := Roles(remotes, o.Lookup, o.Overrides)
	if err != nil {
		return nil, err
	}
	var note string
	switch res.Outcome {
	case Resolved:
	case NeedFork:
		note = "the host has no fork of yours yet: init went on, and `zn pr` will need one (" + res.Reason + ")"
	default:
		why := res.Reason
		if res.Settle != "" {
			why += ": " + res.Settle
		}
		return nil, fmt.Errorf("host: zn cannot work out which remote is the upstream and which is your fork (%s): %s", res.Outcome, why)
	}
	project := o.Project
	if project != "" {
		if err := checkProjectName(project); err != nil {
			return nil, fmt.Errorf("host: --project: %w", err)
		}
	} else if project, err = projectName(res.Upstream.ID.Repo); err != nil {
		return nil, fmt.Errorf("host: %w (name the project with --project <name>)", err)
	}

	trackerDir := filepath.Join(root, ".tracker")
	var tr *Repo
	exists, err := checkTrackerFolder(trackerDir, trackerID, &tr)
	if err != nil {
		return nil, err
	}
	hide := hideFile{root: root, gitignore: o.Gitignore}
	if err := hide.check(); err != nil {
		return nil, err
	}
	if !exists {
		if err := verifyAddress(hostRepo, "the tracker address", trackerID, "ls-remote", "--get-url", o.Tracker); err != nil {
			return nil, err
		}
	}

	// every check has passed: the writes begin
	// created is true only when this run's own os.Mkdir made .tracker. It is the one thing that lets init remove
	// anything: fail below (the only removal) does so only then, so a folder this run did not make is never touched.
	created := false
	fail := func(err error) ([]string, error) {
		if created {
			os.RemoveAll(trackerDir)
		}
		return steps, err
	}
	if !exists {
		if beforeClone != nil {
			beforeClone()
		}
		if err := os.Mkdir(trackerDir, 0o755); err != nil { // exclusive: git would also refuse, but never delete what is not ours
			return steps, errors.New("host: .tracker appeared while zn init was running (is another zn init running?): zn left it alone")
		}
		created = true
		if err := cloneTracker(hostRepo, o.Tracker, trackerDir); err != nil {
			return fail(err)
		}
		steps = append(steps, "cloned the tracker to .tracker")
		if tr, err = openTracker(trackerDir); err != nil {
			return fail(err)
		}
		if err := verifyOrigin(tr, trackerID); err != nil {
			return fail(err)
		}
	}
	history, err := trackerHasHistory(tr)
	if err != nil {
		return fail(err)
	}
	if history {
		// an empty index means nothing was checked out (a fresh clone, or one cut short before its checkout)
		if staged, err := tr.readGit("ls-files"); err != nil {
			return fail(err)
		} else if strings.TrimSpace(staged) == "" {
			// advisory: the checkout below runs with no user config, so no driver is defined for a filter= to name
			if err := tr.checkAttributes("refs/remotes/origin/main"); err != nil {
				return fail(fmt.Errorf("host: the tracker repository cannot be checked out: %w", err))
			}
			if err := tr.checkoutMain(); err != nil {
				return fail(err)
			}
			steps = append(steps, "checked out main in .tracker")
		}
	}
	added, err := hide.apply()
	if err != nil {
		return steps, err
	}
	if len(added) > 0 {
		if o.Gitignore {
			steps = append(steps, "added "+strings.Join(added, ", ")+" to the host's .gitignore (the file changed in your working tree and is not committed: commit it yourself)")
		} else {
			steps = append(steps, "added "+strings.Join(added, ", ")+" to .git/info/exclude (this clone only: nothing tracked changes)")
		}
	}
	if err := hide.verifyIgnored(hostRepo); err != nil {
		return steps, err
	}
	if !history {
		if _, err := tr.readGit("rev-parse", "--verify", "-q", "refs/heads/main"); err != nil { // not committed yet
			if err := initialiseTracker(tr, project); err != nil {
				return steps, err
			}
			steps = append(steps, "initialised the empty tracker for "+project+": README.md, .gitignore, z-nile/projects.toml and "+project+"/.tracker/, committed on main")
		}
		if _, err := tr.readGit("cat-file", "-e", "refs/heads/main:z-nile/projects.toml"); err != nil {
			held, _ := tr.readGit("ls-tree", "--name-only", "refs/heads/main")
			return steps, fmt.Errorf("host: the local main of .tracker has no z-nile/projects.toml (it holds: %s), so zn will not push it: move .tracker away, or add the registry yourself", strings.Join(strings.Fields(held), ", "))
		}
		if _, err := tr.write("push", "--receive-pack=git-receive-pack", "-u", "origin", "refs/heads/main:refs/heads/main"); err != nil {
			return steps, fmt.Errorf("host: pushing main to the tracker failed (run zn init again to retry): %w", err)
		}
		steps = append(steps, "pushed main to the tracker")
	}
	if note != "" {
		steps = append(steps, note)
	}
	return steps, nil
}

// beforeClone is a test seam called between the checks and the creation of .tracker.
var beforeClone func()

// checkoutMain checks out the tracker's main from exactly refs/remotes/origin/main (or, when a local main exists, from
// refs/heads/main: full names, so a tag or another branch called main never wins), with no user config at all: the
// reads environment pins the global and system config to nothing, so no filter driver, attributes macro or hook the
// user defined can run on content the tracker's owner controls.
func (r *Repo) checkoutMain() error {
	if err := r.checkLocalConfig(); err != nil {
		return err
	}
	args := append(append([]string{}, readPins...), "-c", "submodule.recurse=false", "checkout", "-q")
	if _, err := r.readGit("rev-parse", "--verify", "-q", "refs/heads/main"); err == nil {
		args = append(args, "refs/heads/main")
	} else {
		args = append(args, "-B", "main", "refs/remotes/origin/main")
	}
	_, err := r.exec(r.reads, args)
	return err
}

// trackerHasHistory decides from the remote, never from the clone's HEAD, whether the tracker repository has history,
// and refuses every state zn must not commit onto: history with no main branch, history with no registry on main,
// or local branches the remote does not have. It asks the network only when the clone has no origin/main yet.
func trackerHasHistory(tr *Repo) (bool, error) {
	if _, err := tr.readGit("rev-parse", "--verify", "-q", "refs/remotes/origin/main"); err == nil {
		if _, err := tr.readGit("cat-file", "-e", "refs/remotes/origin/main:z-nile/projects.toml"); err != nil {
			return false, errors.New("host: the tracker repository has history but no z-nile/projects.toml on its main branch, so it is not a z-nile tracker: zn init will not add to it. Use an empty repository, or add the registry (z-nile/projects.toml) yourself")
		}
		return true, nil
	}
	out, err := tr.effective("ls-remote", "--upload-pack=git-upload-pack", "origin") // writes nothing: no hooks folder is made
	if err != nil {
		return false, fmt.Errorf("host: asking the tracker repository what it holds failed: %w", err)
	}
	if strings.TrimSpace(out) != "" {
		return false, errors.New("host: the tracker repository is not empty but has no `main` branch in .tracker (its history is on another branch, or an earlier clone was cut short): zn works on main and never commits onto it. Rename its branch to main, or move .tracker away and run zn init again")
	}
	refs, err := tr.readGit("for-each-ref", "--format=%(refname)", "refs/heads")
	if err != nil {
		return false, err
	}
	for _, ref := range strings.Fields(refs) {
		if ref != "refs/heads/main" {
			return false, fmt.Errorf("host: .tracker has the local branch %q that the tracker repository does not: zn will not initialise over it", strings.TrimPrefix(ref, "refs/heads/"))
		}
	}
	return false, nil
}

// effective runs a read-only git command with the user's config, so url rewrites (insteadOf, pushInsteadOf) apply.
func (r *Repo) effective(args ...string) (string, error) {
	return r.exec(r.writes, append(append([]string{}, readPins...), args...))
}

// verifyAddress runs a git command that prints one address after every rewrite and refuses unless it names want.
// It never prints the address.
func verifyAddress(r *Repo, what string, want RemoteID, args ...string) error {
	out, err := r.effective(args...)
	if err != nil {
		return err
	}
	for _, addr := range strings.Fields(out) { // every address: a push goes to all of them
		if CheckAddress(addr) != nil {
			return fmt.Errorf("host: %s is rewritten by the git config (an insteadOf or pushInsteadOf rule, or a pushurl) to an address zn cannot use", what)
		}
		if id, err := ParseRemote(addr); err != nil || !id.Same(want) {
			return fmt.Errorf("host: %s is rewritten by the git config (an insteadOf or pushInsteadOf rule, or a pushurl) to another repository, so zn would clone from or push to a repository you did not name: remove that rule", what)
		}
	}
	return nil
}

// verifyOrigin checks the tracker clone's origin after every rewrite, for fetching and for pushing.
func verifyOrigin(tr *Repo, want RemoteID) error {
	if err := verifyAddress(tr, ".tracker's origin (fetch)", want, "remote", "get-url", "--all", "origin"); err != nil {
		return err
	}
	return verifyAddress(tr, ".tracker's origin (push)", want, "remote", "get-url", "--push", "--all", "origin")
}

// checkTrackerFolder says whether <root>/.tracker exists and, when it does, refuses unless it is a plain folder that
// is the top of its own repository, a clone of the tracker address (for fetching and pushing, after rewrites), whose
// config a write would accept.
func checkTrackerFolder(dir string, want RemoteID, tr **Repo) (bool, error) {
	st, err := os.Lstat(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, fmt.Errorf("host: .tracker cannot be read: %w", err)
	}
	switch {
	case st.Mode()&fs.ModeSymlink != 0:
		return false, errors.New("host: .tracker is a symbolic link: zn keeps the tracker in a folder of its own inside the host, so move the link away")
	case !st.IsDir():
		return false, errors.New("host: .tracker is a file, not a clone of the tracker: move it away")
	}
	notClone := func(why string) error {
		return fmt.Errorf("host: .tracker exists and is not a clone of the tracker address given (%s): move it away, or run zn init with the address it was cloned from", why)
	}
	if g, err := os.Lstat(filepath.Join(dir, ".git")); err != nil || !g.IsDir() {
		return false, notClone("it is not the top of its own git repository")
	}
	r, err := openTracker(dir)
	if err != nil {
		return false, notClone("its repository cannot be read")
	}
	remotes, err := r.Remotes()
	if err != nil {
		return false, err
	}
	ok := false
	for _, rm := range remotes {
		if rm.Name == "origin" && rm.Err == nil && rm.NoIdentity == nil && rm.Fetch.Same(want) {
			ok = true
		}
	}
	if !ok {
		return false, notClone("its origin is another repository")
	}
	if err := r.checkLocalConfig(); err != nil {
		return false, fmt.Errorf("host: .tracker: %w", err)
	}
	if err := verifyOrigin(r, want); err != nil {
		return false, err
	}
	*tr = r
	return true, nil
}

// openTracker opens the tracker clone with the tracker itself as the confined root.
func openTracker(dir string) (*Repo, error) {
	return Open(dir, dir, filepath.Join(dir, ".cache", "nohooks"))
}

// cloneTracker clones the tracker address to dest without checking anything out (the caller looks at the tracker's
// attributes first), with the pins of every write, the remote named origin whatever clone.defaultRemoteName says, no
// template (so no hook of the user's template is copied in), no program named by a protocol, and git's own upload-pack.
// The user's global git config applies (credentials, proxies, ssh): the caller has checked what it does to the address.
func cloneTracker(host *Repo, address, dest string) error {
	_, err := host.exec(host.writes, []string{
		"-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "protocol.ext.allow=never", "-c", "protocol.fd.allow=never",
		"-c", "gc.auto=0", "-c", "maintenance.auto=false",
		"-c", "submodule.recurse=false",
		"clone", "-q", "--no-checkout", "-o", "origin", "--template=", "--upload-pack=git-upload-pack", "--", address, dest,
	})
	if err != nil {
		return fmt.Errorf("host: cloning the tracker failed: %w", err)
	}
	return nil
}

// initialiseTracker writes the minimal skeleton into an empty tracker clone and commits it on main. It writes only
// files that do not exist yet and adds exactly those paths.
func initialiseTracker(tr *Repo, project string) error {
	files := trackerSkeleton(project)
	var names []string
	for _, f := range files {
		p := filepath.Join(tr.root, filepath.FromSlash(f.name))
		if err := mkdirConfined(tr.root, filepath.Dir(filepath.FromSlash(f.name))); err != nil {
			return err
		}
		if st, err := os.Lstat(p); err == nil {
			// an earlier run that stopped before its commit (no git identity) left the file: the same text is fine
			b, rerr := os.ReadFile(p)
			if st.Mode().IsRegular() && rerr == nil && string(b) == f.body {
				names = append(names, f.name)
				continue
			}
			return fmt.Errorf("host: .tracker/%s already exists and is not what zn would write: move it away or commit it yourself", f.name)
		}
		h, err := os.OpenFile(p, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
		if err != nil {
			return fmt.Errorf("host: .tracker/%s: %w", f.name, err)
		}
		_, err = h.WriteString(f.body)
		if cerr := h.Close(); err == nil {
			err = cerr
		}
		if err != nil {
			return err
		}
		names = append(names, f.name)
	}
	if _, err := tr.write("symbolic-ref", "HEAD", "refs/heads/main"); err != nil {
		return err
	}
	if _, err := tr.write(append([]string{"add", "--"}, names...)...); err != nil {
		return err
	}
	if _, err := tr.write("commit", "-q", "-m", "Initialise the z-nile tracker for "+project); err != nil {
		return fmt.Errorf("host: committing the skeleton failed (git needs your user.name and user.email): %w", err)
	}
	return nil
}

// mkdirConfined makes the folders of rel under root one component at a time, refusing a component that is a link or a
// file, so nothing is ever written outside root through a link the tracker's content planted.
func mkdirConfined(root, rel string) error {
	cur := root
	for _, part := range strings.Split(rel, string(filepath.Separator)) {
		if part == "." || part == "" {
			continue
		}
		cur = filepath.Join(cur, part)
		st, err := os.Lstat(cur)
		switch {
		case errors.Is(err, fs.ErrNotExist):
			if err := os.Mkdir(cur, 0o755); err != nil {
				return err
			}
		case err != nil:
			return err
		case st.Mode()&fs.ModeSymlink != 0:
			return fmt.Errorf("host: .tracker/%s is a symbolic link: zn will not write the skeleton through a link", filepath.ToSlash(strings.TrimPrefix(cur, root+string(filepath.Separator))))
		case !st.IsDir():
			return fmt.Errorf("host: .tracker/%s is a file where zn needs a folder", filepath.ToSlash(strings.TrimPrefix(cur, root+string(filepath.Separator))))
		}
	}
	return nil
}

type skeletonFile struct{ name, body string }

// trackerSkeleton is the minimal tracker the engine reads: the project registry with the one project, its two item
// folders (git holds a folder through a file), the tracker's own .gitignore for machine-local state, and a README. It
// holds no tributaries file, no settings and no host table: later steps add what they need.
func trackerSkeleton(project string) []skeletonFile {
	readme := "# " + project + " tracker\n\n" +
		"This repository is the public work record of the z-nile pipeline for the host project `" + project + "`: its tickets, designs, reviews, rafts, guesses and lessons. " +
		"It is written by tooling (`zn`), not by hand, and everything committed to it is public.\n\n" +
		"## Layout\n\n" +
		"- `z-nile/projects.toml` lists the projects this tracker holds.\n" +
		"- `" + project + "/.tracker/issues/` holds one folder per ticket.\n" +
		"- `" + project + "/.tracker/rafts/` holds the rafts, which group tickets into one delivery.\n\n" +
		"The host project's own code is not here: it lives in the host repository and reaches it through pull requests.\n"
	registry := "# The projects this tracker holds. Written by `zn init`; read by z-nile's engine.\n" +
		"retired = []\n\n[[project]]\nname = \"" + project + "\"\nroot = \"" + project + "/.tracker\"\n"
	return []skeletonFile{
		{"README.md", readme},
		{".gitignore", "# machine-local state zn keeps in this checkout\n.cache/\nprompt.md\n.worktree/\n"},
		{"z-nile/projects.toml", registry},
		{project + "/.tracker/issues/.gitkeep", ""},
		{project + "/.tracker/rafts/.gitkeep", ""},
	}
}

var (
	notNameChar = regexp.MustCompile(`[^a-z0-9]+`)
	nameWords   = regexp.MustCompile(`^[a-z][a-z0-9]*$`)
	nameHyphens = regexp.MustCompile(`^[a-z][a-z0-9-]*[a-z0-9]$`)
	// reservedProjects are folders of a tracker that a project's home must not be: the registry's own and the
	// folders every project home holds.
	reservedProjects = map[string]bool{"z-nile": true, "tracker": true, "src": true, "tests": true, "skills": true, "scripts": true}
)

// checkProjectName applies the engine's grammar (z-nile/engine/projects.luau nameOk: lower-case words joined by single
// hyphens, a leading letter) and refuses the names a tracker's own folders use.
func checkProjectName(n string) error {
	if !(nameWords.MatchString(n) || (nameHyphens.MatchString(n) && !strings.Contains(n, "--"))) {
		return fmt.Errorf("the project name %q is not lower-case words joined by single hyphens, starting with a letter", n)
	}
	if reservedProjects[n] {
		return fmt.Errorf("the project name %q is reserved: the tracker uses that folder itself", n)
	}
	return nil
}

// projectName turns the upstream repository's name (or, for a local path, its last folder) into a project name in the
// engine's grammar: lower-case ASCII words joined by single hyphens, and a leading digit gets the prefix "p-". It
// refuses a name with characters outside ASCII letters, digits, dots, underscores and hyphens (they would be dropped
// and two repositories could collapse into one name), an empty name and a reserved one.
func projectName(repo string) (string, error) {
	base := strings.TrimSuffix(path.Base(repo), ".git")
	if repo == "" || base == "." || base == "/" {
		return "", errors.New("the upstream repository has no name to derive a project name from")
	}
	for _, r := range base {
		if !(r < 0x80 && (r == '.' || r == '_' || r == '-' || r == ' ' || r >= '0' && r <= '9' || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z')) {
			return "", fmt.Errorf("the upstream repository's name %q has characters a project name cannot hold", base)
		}
	}
	n := strings.Trim(notNameChar.ReplaceAllString(strings.ToLower(base), "-"), "-")
	if n != "" && n[0] >= '0' && n[0] <= '9' {
		n = "p-" + n
	}
	if n == "" {
		return "", fmt.Errorf("the upstream repository's name %q leaves no project name", base)
	}
	if err := checkProjectName(n); err != nil {
		return "", err
	}
	return n, nil
}

// hideFile is how zn's three folders are kept out of the host: lines in info/exclude (the default) or in the tracked
// .gitignore (--gitignore).
type hideFile struct {
	root      string
	gitignore bool
}

func (h hideFile) path() string {
	if h.gitignore {
		return filepath.Join(h.root, ".gitignore")
	}
	return filepath.Join(h.root, ".git", "info", "exclude")
}

func (h hideFile) label() string {
	if h.gitignore {
		return ".gitignore"
	}
	return ".git/info/exclude"
}

// check refuses a file that is a link, a folder or under a link, because a write would then leave the host.
func (h hideFile) check() error {
	if !h.gitignore {
		if st, err := os.Lstat(filepath.Dir(h.path())); err == nil && st.Mode()&fs.ModeSymlink != 0 {
			return fmt.Errorf("host: .git/info is a symbolic link: zn will not write info/exclude through a link")
		}
	}
	st, err := os.Lstat(h.path())
	switch {
	case errors.Is(err, fs.ErrNotExist):
		return nil
	case err != nil:
		return fmt.Errorf("host: %s cannot be read: %w", h.label(), err)
	case st.Mode()&fs.ModeSymlink != 0:
		return fmt.Errorf("host: %s is a symbolic link: zn will not write through a link, so replace it with a plain file", h.label())
	case !st.Mode().IsRegular():
		return fmt.Errorf("host: %s is not a plain file", h.label())
	}
	return nil
}

// missing lists the folder lines the file does not hold yet, in any of the spellings git reads the same way.
func missing(text string) []string {
	have := map[string]bool{}
	for _, l := range strings.Split(text, "\n") {
		have[strings.Trim(strings.TrimRight(l, " \t\r"), "/")] = true
	}
	var out []string
	for _, f := range znFolders {
		if !have[strings.Trim(f, "/")] {
			out = append(out, f)
		}
	}
	return out
}

// apply appends the missing lines and returns them.
func (h hideFile) apply() ([]string, error) {
	var text string
	mode := fs.FileMode(0o644)
	if b, err := os.ReadFile(h.path()); err == nil {
		text = string(b)
		if st, err := os.Stat(h.path()); err == nil {
			mode = st.Mode().Perm()
		}
	} else if !errors.Is(err, fs.ErrNotExist) {
		return nil, err
	}
	add := missing(text)
	if len(add) == 0 {
		return nil, nil
	}
	if text != "" && !strings.HasSuffix(text, "\n") {
		text += "\n"
	}
	if err := os.MkdirAll(filepath.Dir(h.path()), 0o755); err != nil {
		return nil, err
	}
	// a temp file in the same folder, renamed into place: a reader never sees half a file, and a link planted since
	// check() is replaced, never written through
	tmp, err := os.CreateTemp(filepath.Dir(h.path()), ".zn-init-*")
	if err != nil {
		return nil, err
	}
	defer os.Remove(tmp.Name())
	_, err = tmp.WriteString(text + strings.Join(add, "\n") + "\n")
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = os.Chmod(tmp.Name(), mode)
	}
	if err != nil {
		return nil, err
	}
	if err := h.check(); err != nil { // immediately before the rename
		return nil, err
	}
	if err := os.Rename(tmp.Name(), h.path()); err != nil {
		return nil, err
	}
	return add, nil
}

// verifyIgnored asks git, with no user-level ignore file, whether each of zn's three folders is ignored in the host,
// so a later line (a negation, a comment, a leading space) that hides nothing is found, not assumed away.
func (h hideFile) verifyIgnored(r *Repo) error {
	for _, f := range znFolders {
		if _, err := r.git("check-ignore", "-q", "--", f+"probe"); err != nil {
			return fmt.Errorf("host: git does not ignore %s in the host after zn's lines were written: another line of %s or of the host's ignore files un-ignores it or comes first (a negation such as !%s): fix that line, then run zn init again", f, h.label(), f)
		}
	}
	return nil
}
