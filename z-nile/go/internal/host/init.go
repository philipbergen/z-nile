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
	Lookup    Lookup    // what GitHub says about the host's remotes; injected, this package never reaches the network
}

// zn's three folders in the host, in the order they are listed in an ignore file.
var znFolders = []string{".tracker/", ".worktree/", ".cache/"}

// Init sets zn up in a host repository: it refuses, naming the cause, before it writes anything; then it clones the
// tracker to <Root>/.tracker (when missing), keeps .tracker out of the host, initialises an empty tracker and pushes
// it. Every step checks before it writes, so a second run takes none. It returns the steps it took, one line each (and
// the steps taken so far with an error that stops it midway). The push is the one outward act: it goes only to
// o.Tracker. The host's own refs, config and tracked files are never written.
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
	project := projectName(res.Upstream.ID.Repo)

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

	// every check has passed: the writes begin
	if !exists {
		if err := cloneTracker(hostRepo, o.Tracker, trackerDir); err != nil {
			return steps, err
		}
		steps = append(steps, "cloned the tracker to .tracker")
		if tr, err = openTracker(trackerDir); err != nil {
			return steps, err
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
	if _, err := tr.readGit("rev-parse", "--verify", "-q", "HEAD"); err != nil { // no commits: an empty tracker
		if err := initialiseTracker(tr, project); err != nil {
			return steps, err
		}
		steps = append(steps, "initialised the empty tracker for "+project+": README.md, .gitignore, z-nile/projects.toml and "+project+"/.tracker/, committed on main")
	}
	_, haveMain := tr.readGit("rev-parse", "--verify", "-q", "refs/heads/main")
	_, pushed := tr.readGit("rev-parse", "--verify", "-q", "refs/remotes/origin/main")
	if haveMain == nil && pushed != nil {
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

// checkTrackerFolder says whether <root>/.tracker exists and, when it does, refuses unless it is a plain folder that
// is the top of its own repository, a clone of the tracker address, whose config a write would accept.
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
	*tr = r
	return true, nil
}

// openTracker opens the tracker clone with the tracker itself as the confined root.
func openTracker(dir string) (*Repo, error) {
	return Open(dir, dir, filepath.Join(dir, ".cache", "nohooks"))
}

// cloneTracker clones the tracker address to dest, with the pins of every write, no template (so no hook of the user's
// template is copied in), no program named by a protocol, and git's own upload-pack.
func cloneTracker(host *Repo, address, dest string) error {
	_, err := host.exec(host.writes, []string{
		"-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "protocol.ext.allow=never", "-c", "protocol.fd.allow=never",
		"-c", "gc.auto=0", "-c", "maintenance.auto=false",
		"clone", "-q", "--template=", "--no-recurse-submodules", "--upload-pack=git-upload-pack", "--", address, dest,
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
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			return err
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

var notNameChar = regexp.MustCompile(`[^a-z0-9]+`)

// projectName turns the upstream repository's name (or, for a local path, its last folder) into a project name:
// lower-case words joined by hyphens, "host" when nothing is left.
func projectName(repo string) string {
	n := strings.Trim(notNameChar.ReplaceAllString(strings.TrimSuffix(strings.ToLower(path.Base(repo)), ".git"), "-"), "-")
	if n == "" || path.Base(repo) == "." {
		return "host"
	}
	return n
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
		have[strings.Trim(strings.TrimSpace(l), "/")] = true
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
	if err := os.WriteFile(h.path(), []byte(text+strings.Join(add, "\n")+"\n"), mode); err != nil {
		return nil, err
	}
	return add, nil
}
