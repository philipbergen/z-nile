package host

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// The front door's reader of the tracker (f0428 step 4). One resolver answers where a host's tracker is and where the
// engine runs, from any folder: the host's own folders, a linked worktree of the host, the tracker's checkout and a
// worktree of the tracker. The engine itself is unchanged: it sees the tracker as a one-project z-nile repository, runs
// in a worktree of it, and publishes to the tracker's origin/main. Nothing here writes into the host.

// TrackerReason names why a host's tracker cannot be used.
type TrackerReason string

// The reasons Locate and Prepare refuse, each its own.
const (
	ReasonTrackerLink  TrackerReason = "tracker-not-a-folder"        // .tracker is a link or not a folder
	ReasonNotClone     TrackerReason = "tracker-not-a-clone"         // not the top of its own repository, no origin/main, unsafe config
	ReasonNoRegistry   TrackerReason = "tracker-no-registry"         // z-nile/projects.toml is missing on origin/main
	ReasonDirty        TrackerReason = "tracker-has-changes"         // uncommitted changes of someone else in the tracker's checkout
	ReasonWorktree     TrackerReason = "tracker-worktree-in-the-way" // the standing worktree is not zn's or holds changes
	ReasonEngineInPlay TrackerReason = "engine-file-in-the-way"      // a real file where an engine link goes
)

// TrackerRefusal is the refusal of a tracker, naming the cause. It never holds a remote's address.
type TrackerRefusal struct {
	Reason TrackerReason
	Detail string
}

func (e *TrackerRefusal) Error() string { return "tracker: " + string(e.Reason) + ": " + e.Detail }

func refuseTracker(r TrackerReason, format string, a ...any) error {
	return &TrackerRefusal{Reason: r, Detail: fmt.Sprintf(format, a...)}
}

// Tracker is the tracker of a host: where it is and where the engine runs.
type Tracker struct {
	Host string // the host's main checkout
	Dir  string // <Host>/.tracker, the tracker's main checkout
	Work string // the checkout the engine runs in: the standing worktree, or the tracker worktree the caller is in
}

// engineLinks are the engine folders and files a tracker checkout links from the extracted payload, so the engine's
// own relative paths (z-nile/lib/fence.sh, z-nile/templates, z-nile/roots...) resolve as they do in a z-nile repository.
var engineLinks = []string{"engine", "lib", "vendor", "templates", "roots.luau", "affected.luau"}

// registryPath is the tracker's registry, the file that makes a repository a zn tracker.
const registryPath = "z-nile/projects.toml"

// trackerFolder and standingName are the tracker's place in the host and the standing worktree's in the tracker.
const (
	trackerFolder = ".tracker"
	standingName  = "zn"
)

// readRepo is a read-only handle on whatever repository holds dir (git finds it), with the program-stopping pins.
func readRepo(dir string) *Repo {
	return &Repo{dir: dir, reads: readEnv(os.Environ(), "")}
}

// gitPlaces is the top level and the common git directory of the repository that holds dir, or ok false when none does.
func gitPlaces(dir string) (top, common string, ok bool) {
	out, err := readRepo(dir).git("rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir")
	if err != nil {
		return "", "", false
	}
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) != 2 {
		return "", "", false
	}
	t, err1 := resolve(lines[0])
	c, err2 := resolve(lines[1])
	if err1 != nil || err2 != nil {
		return "", "", false
	}
	return t, c, true
}

// Locate finds the tracker of the host that cwd belongs to, or nil, nil when none applies: cwd is in no repository, in
// one that has no .tracker beside its .git (a repository like this one keeps its tickets inside itself), or in a
// repository whose git directory is not an ordinary `<root>/.git`. It only reads. When a tracker applies it refuses,
// naming the cause, a host that tracks .tracker or has program-running local config (CheckHost), a .tracker that is a
// link, not a folder, not the top of a clone of its own, unsafe in its config or without origin/main, a tracker whose
// origin/main has no registry, and a tracker checkout with uncommitted changes of someone else.
func Locate(cwd string) (*Tracker, error) {
	real, err := resolve(cwd)
	if err != nil {
		return nil, nil
	}
	if st, err := os.Stat(real); err != nil || !st.IsDir() {
		return nil, nil
	}
	top, common, ok := gitPlaces(real)
	if !ok || filepath.Base(common) != ".git" {
		return nil, nil
	}
	main := filepath.Dir(common)
	t := &Tracker{}
	if _, err := os.Stat(filepath.Join(top, filepath.FromSlash(registryPath))); err == nil && filepath.Base(main) == trackerFolder {
		// inside the tracker: its main checkout, its standing worktree or a worktree of its own
		t.Dir, t.Host = main, filepath.Dir(main)
		t.Work = filepath.Join(t.Dir, ".worktree", standingName)
		if top != main {
			t.Work = top
		}
	} else {
		t.Host, t.Dir = main, filepath.Join(main, trackerFolder)
		t.Work = filepath.Join(t.Dir, ".worktree", standingName)
		if _, err := os.Lstat(t.Dir); err != nil {
			return nil, nil
		}
	}
	if err := CheckHost(t.Host); err != nil {
		return nil, err
	}
	if err := t.check(); err != nil {
		return nil, err
	}
	return t, nil
}

// check is every refusal of the tracker itself, all reads.
func (t *Tracker) check() error {
	st, err := os.Lstat(t.Dir)
	switch {
	case err != nil:
		return refuseTracker(ReasonTrackerLink, ".tracker cannot be read: %v", err)
	case st.Mode()&fs.ModeSymlink != 0:
		return refuseTracker(ReasonTrackerLink, ".tracker is a symbolic link: zn works only in a clone that is a folder of the host")
	case !st.IsDir():
		return refuseTracker(ReasonTrackerLink, ".tracker is not a folder")
	}
	top, common, ok := gitPlaces(t.Dir)
	if !ok || top != t.Dir || common != filepath.Join(t.Dir, ".git") {
		return refuseTracker(ReasonNotClone, ".tracker is not the top of a clone of a tracker of its own (a plain folder, or a separate git directory): run zn init in the host, or remove it yourself")
	}
	tr, err := openTracker(t.Dir)
	if err != nil {
		return refuseTracker(ReasonNotClone, "%v", err)
	}
	if err := tr.checkLocalConfig(); err != nil {
		return refuseTracker(ReasonNotClone, "%s", strings.TrimPrefix(err.Error(), "host: refusing to run git: "))
	}
	if _, err := tr.git("rev-parse", "--verify", "-q", "refs/remotes/origin/main^{commit}"); err != nil {
		return refuseTracker(ReasonNotClone, ".tracker has no origin/main: run zn init in the host again")
	}
	if err := tr.checkRegistry(); err != nil {
		return err
	}
	out, err := tr.git("status", "--porcelain=v1", "-z", "--untracked-files=normal")
	if err != nil {
		return err
	}
	if paths := statusPaths(out); len(paths) > 0 {
		return refuseTracker(ReasonDirty, ".tracker has changes that zn did not make (%s): commit or discard them in .tracker, then run the command again", listPaths(paths))
	}
	return nil
}

// checkRegistry refuses a tracker whose origin/main has no registry: the engine reads the roots from nothing else.
func (r *Repo) checkRegistry() error {
	if _, err := r.git("cat-file", "-e", "refs/remotes/origin/main:"+registryPath); err != nil {
		return refuseTracker(ReasonNoRegistry, "%s is missing on the tracker's origin/main, so this is not a zn tracker", registryPath)
	}
	return nil
}

// statusPaths are the paths of a `status --porcelain=v1 -z` listing.
func statusPaths(out string) []string {
	var paths []string
	parts := strings.Split(out, "\x00")
	for i := 0; i < len(parts); i++ { // a rename carries a second path
		e := parts[i]
		if len(e) < 4 {
			continue
		}
		paths = append(paths, e[3:])
		if e[0] == 'R' || e[0] == 'C' {
			i++
		}
	}
	return paths
}

func listPaths(paths []string) string {
	if len(paths) > 3 {
		return strings.Join(paths[:3], ", ") + fmt.Sprintf(" and %d more", len(paths)-3)
	}
	return strings.Join(paths, ", ")
}

// Prepare makes Work ready for the engine and returns the steps it took (none when nothing was to do): it fetches the
// tracker's main, makes or moves the standing worktree to it (detached; the tracker's own branch is never moved), hides
// the engine links and the worktree folder in the tracker's own exclude file, and links the engine from payloadDir. It
// writes only inside the tracker. A fetch that fails is a step, not an error: the work goes on from origin/main as last
// fetched.
func (t *Tracker) Prepare(payloadDir string) ([]string, error) {
	var steps []string
	for _, n := range engineLinks {
		if _, err := os.Stat(filepath.Join(payloadDir, "z-nile", n)); err != nil {
			return nil, fmt.Errorf("tracker: the engine payload %q lacks z-nile/%s", payloadDir, n)
		}
	}
	tr, err := openTracker(t.Dir)
	if err != nil {
		return nil, refuseTracker(ReasonNotClone, "%v", err)
	}
	if err := tr.FetchDefault("origin", "main"); err != nil {
		steps = append(steps, "could not fetch the tracker, working from its origin/main as last fetched")
	} else if err := tr.checkRegistry(); err != nil {
		return nil, err
	}
	hide := hideFile{root: t.Dir, lines: append([]string{"/.worktree/"}, linkLines()...)}
	if err := hide.check(); err != nil {
		return nil, refuseTracker(ReasonNotClone, "%v", err)
	}
	if t.Work == filepath.Join(t.Dir, ".worktree", standingName) {
		s, err := t.standing(tr)
		steps = append(steps, s...)
		if err != nil {
			return steps, err
		}
	}
	added, err := hide.apply()
	if err != nil {
		return steps, err
	}
	if len(added) > 0 {
		steps = append(steps, "hid the engine links in the tracker's .git/info/exclude")
	}
	for _, n := range engineLinks {
		made, err := ensureLink(filepath.Join(t.Work, "z-nile", n), filepath.Join(payloadDir, "z-nile", n))
		if err != nil {
			return steps, err
		}
		if made {
			steps = append(steps, "linked z-nile/"+n+" in "+t.Work)
		}
	}
	return steps, nil
}

func linkLines() []string {
	var out []string
	for _, n := range engineLinks {
		out = append(out, "/z-nile/"+n)
	}
	return out
}

// standing makes the standing worktree, or moves it to origin/main.
func (t *Tracker) standing(tr *Repo) ([]string, error) {
	abs, err := resolve(t.Work)
	if err != nil || !within(tr.root, abs) {
		return nil, refuseTracker(ReasonWorktree, "the standing worktree %q would be outside .tracker", t.Work)
	}
	want, err := tr.git("rev-parse", "--verify", "refs/remotes/origin/main^{commit}")
	if err != nil {
		return nil, err
	}
	want = strings.TrimSpace(want)
	st, err := os.Lstat(abs)
	if errors.Is(err, fs.ErrNotExist) {
		if err := tr.checkAttributes("refs/remotes/origin/main"); err != nil {
			return nil, err
		}
		if _, err := tr.write("worktree", "add", "-q", "--detach", abs, "refs/remotes/origin/main"); err != nil {
			return nil, err
		}
		return []string{"made the standing worktree .tracker/.worktree/" + standingName}, nil
	}
	if err != nil {
		return nil, err
	}
	_, common, ok := gitPlaces(abs)
	if st.Mode()&fs.ModeSymlink != 0 || !st.IsDir() || !ok || common != filepath.Join(t.Dir, ".git") {
		return nil, refuseTracker(ReasonWorktree, ".tracker/.worktree/%s is not a worktree of the tracker: remove it, and zn makes it again", standingName)
	}
	w, err := Open(tr.root, abs, filepath.Join(tr.root, ".cache", "nohooks"))
	if err != nil {
		return nil, refuseTracker(ReasonWorktree, "%v", err)
	}
	have, err := w.git("rev-parse", "--verify", "HEAD")
	if err != nil {
		return nil, err
	}
	out, err := w.git("status", "--porcelain=v1", "-z", "--untracked-files=no")
	if err != nil {
		return nil, err
	}
	if paths := statusPaths(out); len(paths) > 0 {
		return nil, refuseTracker(ReasonWorktree, ".tracker/.worktree/%s has changed files (%s): commit or discard them there, then run the command again", standingName, listPaths(paths))
	}
	if strings.TrimSpace(have) == want {
		return nil, nil
	}
	if err := w.checkAttributes("refs/remotes/origin/main"); err != nil {
		return nil, err
	}
	if _, err := w.write("checkout", "-q", "--detach", "refs/remotes/origin/main"); err != nil {
		return nil, refuseTracker(ReasonWorktree, "moving .tracker/.worktree/%s to the tracker's main failed: %v", standingName, err)
	}
	return []string{"moved the standing worktree to the tracker's main (" + want[:7] + ")"}, nil
}

// ensureLink makes path a link to target, replacing a link that points elsewhere; a real file or folder there is
// refused, because it is not zn's.
func ensureLink(path, target string) (bool, error) {
	st, err := os.Lstat(path)
	switch {
	case err == nil && st.Mode()&fs.ModeSymlink != 0:
		if got, _ := os.Readlink(path); got == target {
			return false, nil
		}
	case err == nil:
		return false, refuseTracker(ReasonEngineInPlay, "the tracker holds a real z-nile/%s where zn links its engine: zn will not replace it", filepath.Base(path))
	case !errors.Is(err, fs.ErrNotExist):
		return false, err
	}
	tmp := path + ".zn-link"
	os.Remove(tmp)
	if err := os.Symlink(target, tmp); err != nil {
		return false, err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return false, err
	}
	return true, nil
}
