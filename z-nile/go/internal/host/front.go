package host

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
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

// TrackerRefusal is the refusal of a tracker: what is wrong, naming the path, then what to do next. It never holds a
// remote's address, and it names every folder by its absolute path.
type TrackerRefusal struct {
	Reason TrackerReason
	Detail string
	Next   string // what to do next: the message's last sentence
}

func (e *TrackerRefusal) Error() string {
	return "tracker: " + strings.TrimRight(e.Detail, ". ") + ". " + e.Next
}

// refuseTracker is every refusal of this file: the reason, what to do next, and the detail.
func refuseTracker(r TrackerReason, next, format string, a ...any) error {
	return &TrackerRefusal{Reason: r, Detail: fmt.Sprintf(format, a...), Next: next}
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
	if !ok {
		for p := real; p != filepath.Dir(p); p = filepath.Dir(p) { // inside the git directory of a tracker, or of a host that has one
			if filepath.Base(p) != ".git" {
				continue
			}
			if filepath.Base(filepath.Dir(p)) == trackerFolder {
				return nil, refuseTracker(ReasonNotClone, "Run zn from a folder of the host or of a worktree of the tracker.", "%s is inside the tracker's git directory %s", real, p)
			}
			if _, err := os.Lstat(filepath.Join(filepath.Dir(p), trackerFolder)); err == nil {
				return nil, unusual(ReasonNotTop, "%q is inside the git directory of a host that has a .tracker: run zn from a folder of the host's working tree", cwd)
			}
		}
		return nil, nil
	}
	if filepath.Base(common) != ".git" {
		if _, err := os.Lstat(filepath.Join(top, trackerFolder)); err == nil { // a separate git directory or a submodule
			if err := CheckHost(top); err != nil {
				return nil, err
			}
			return nil, unusual(ReasonGitfile, "%q has a .tracker but its git directory is not %q: zn cannot tell where the host's main checkout is", top, filepath.Join(top, ".git"))
		}
		return nil, nil
	}
	main := filepath.Dir(common)
	t := &Tracker{}
	if filepath.Base(main) == trackerFolder { // a clone named .tracker is the tracker, whatever its worktree holds: check() judges it
		// inside the tracker: its main checkout, its standing worktree or a worktree of its own
		t.Dir, t.Host = main, filepath.Dir(main)
		t.Work = filepath.Join(t.Dir, ".worktree", standingName)
		if top != main {
			if wt := filepath.Join(t.Dir, ".worktree"); top == wt || !within(wt, top) {
				return nil, refuseTracker(ReasonWorktree, "Run zn from the host, or from a worktree of the tracker made under that .worktree folder.", "%s is a worktree of the tracker outside %s, where zn keeps its worktrees", top, wt)
			}
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
		return refuseTracker(ReasonTrackerLink, "Check that folder's permissions, then run the command again.", "%s cannot be read: %v", t.Dir, err)
	case st.Mode()&fs.ModeSymlink != 0:
		return refuseTracker(ReasonTrackerLink, "Move the clone itself to that place instead of the link, then run the command again.", "%s is a symbolic link: zn works only in a clone that is a folder of the host", t.Dir)
	case !st.IsDir():
		return refuseTracker(ReasonTrackerLink, "Move it away, then run zn init in the host.", "%s is not a folder", t.Dir)
	}
	top, common, ok := gitPlaces(t.Dir)
	if !ok || top != t.Dir || common != filepath.Join(t.Dir, ".git") {
		return refuseTracker(ReasonNotClone, "Run zn init in the host, or move the folder away yourself.", "%s is not the top of a clone of a tracker of its own (a plain folder, a worktree, a separate or linked git directory)", t.Dir)
	}
	tr, err := openTracker(t.Dir)
	if err != nil {
		return refuseTracker(ReasonNotClone, "Run zn init in the host again.", "%v", err)
	}
	if err := tr.checkLocalConfig(); err != nil {
		return refuseTracker(ReasonNotClone, "Remove that setting from the tracker's config, then run the command again.", "%s", strings.TrimPrefix(err.Error(), "host: refusing to run git: "))
	}
	if _, err := tr.git("rev-parse", "--verify", "-q", "refs/remotes/origin/main^{commit}"); err != nil {
		return refuseTracker(ReasonNotClone, "Run zn init in the host again.", "%s has no origin/main", t.Dir)
	}
	if err := tr.checkData("refs/remotes/origin/main", "the tracker's origin/main"); err != nil {
		return err
	}
	if err := tr.checkRegistry(); err != nil {
		return err
	}
	if err := tr.checkData("HEAD", "the tracker's checkout "+t.Dir); err != nil {
		return err
	}
	out, err := tr.git("status", "--porcelain=v1", "-z", "--untracked-files=normal")
	if err != nil {
		return err
	}
	if paths := statusPaths(out); len(paths) > 0 {
		return refuseTracker(ReasonDirty, "Commit or discard them there, then run the command again.", "%s has changes that zn did not make (%s)", t.Dir, listPaths(paths))
	}
	return checkFiles(t.Dir, false)
}

// checkRegistry refuses a tracker whose origin/main has no registry: the engine reads the roots from nothing else.
func (r *Repo) checkRegistry() error {
	if _, err := r.git("cat-file", "-e", "refs/remotes/origin/main:"+registryPath); err != nil {
		return refuseTracker(ReasonNoRegistry, "Add it to the tracker's main (zn init writes it), or point the host at a zn tracker.", "%s is missing on the tracker's origin/main, so this is not a zn tracker", registryPath)
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

// Prepare makes Work ready for the engine and returns the steps it took (none when nothing was to do). In order: it
// refuses a folder zn writes through (.git, .git/info, .worktree, the standing worktree) that is a link; refuses an
// origin whose effective fetch or push address the git config rewrites; fetches the tracker's main (a failed fetch is a
// step, not an error: the work goes on from origin/main as last fetched); refuses a tracker tree that is not data;
// makes or moves the standing worktree (detached; the tracker's own branch is never moved, and a commit that is not on
// origin/main is never left behind); refuses a linked .cache there and checks the worktree's own tree; hides the engine
// links and the worktree folder in the tracker's exclude file; asks git whether every path zn owns is ignored; links the
// engine from payloadDir, each link confined to a real z-nile folder inside the worktree; refuses a file on disk at a
// path zn owns; and last, just before the engine pushes from it, checks the worktree's own config and its effective
// push address. It writes only inside the tracker. The caller holds the tracker's lock (LockTracker) for the whole
// command.
func (t *Tracker) Prepare(payloadDir string) ([]string, error) {
	var steps []string
	for _, n := range engineLinks {
		if _, err := os.Stat(filepath.Join(payloadDir, "z-nile", n)); err != nil {
			return nil, refuseTracker(ReasonEngineInPlay, "Remove that folder, and zn extracts its engine again on its next run.", "the engine zn extracted to %s lacks z-nile/%s", payloadDir, n)
		}
	}
	tr, err := openTracker(t.Dir)
	if err != nil {
		return nil, refuseTracker(ReasonNotClone, "Run zn init in the host again.", "%v", err)
	}
	if err := plainFolders(t.Dir, ReasonNotClone, "Make it the clone's own folder again (or clone the tracker anew with zn init), then run the command again.", ".git", ".git/info"); err != nil {
		return nil, err
	}
	if err := plainFolders(t.Dir, ReasonWorktree, "Remove the link (zn makes the folder itself), then run the command again.", ".worktree", ".worktree/"+standingName); err != nil {
		return nil, err
	}
	if err := checkOriginAddress(tr); err != nil {
		return nil, err
	}
	if err := tr.FetchDefault("origin", "main"); err != nil {
		steps = append(steps, "could not fetch the tracker, working from its origin/main as last fetched")
	}
	if err := tr.checkData("refs/remotes/origin/main", "the tracker's origin/main"); err != nil {
		return nil, err
	}
	if err := tr.checkRegistry(); err != nil {
		return nil, err
	}
	hide := hideFile{root: t.Dir, lines: append([]string{"/.worktree/"}, linkLines()...)}
	if err := hide.check(); err != nil {
		return nil, refuseTracker(ReasonNotClone, "Make it a plain file of the tracker's own git directory, then run the command again.", "%s: %v", hide.path(), err)
	}
	if t.Work == filepath.Join(t.Dir, ".worktree", standingName) {
		s, err := t.standing(tr)
		steps = append(steps, s...)
		if err != nil {
			return steps, err
		}
	}
	if err := plainFolders(t.Work, ReasonWorktree, "Remove the link (the engine makes the folder itself), then run the command again.", ".cache"); err != nil {
		return steps, err
	}
	head, err := readRepo(t.Work).git("rev-parse", "--verify", "HEAD^{commit}")
	if err != nil {
		return steps, refuseTracker(ReasonWorktree, "Run zn from the host, or from a worktree of the tracker.", "%s is not a worktree of the tracker", t.Work)
	}
	if err := tr.checkData(strings.TrimSpace(head), "the checkout "+t.Work); err != nil {
		return steps, err
	}
	added, err := hide.apply()
	if err != nil {
		return steps, err
	}
	if len(added) > 0 {
		steps = append(steps, "hid the engine links in "+hide.path())
	}
	if err := t.checkIgnored(); err != nil {
		return steps, err
	}
	if err := t.checkZNileFolder(); err != nil {
		return steps, err
	}
	for _, n := range engineLinks {
		p := filepath.Join(t.Work, "z-nile", n)
		made, err := ensureLink(p, filepath.Join(payloadDir, "z-nile", n))
		if err != nil {
			return steps, err
		}
		if made {
			steps = append(steps, "linked "+p)
		}
	}
	if err := checkFiles(t.Work, true); err != nil {
		return steps, err
	}
	return steps, t.checkPushFrom(tr)
}

// checkPushFrom is the last check before the engine starts in Work and pushes from it: Work's own config (a worktree's
// config.worktree, when the tracker turns that extension on) holds nothing a write would refuse, and origin's
// effective fetch and push addresses, as git resolves them in Work, are origin's own.
func (t *Tracker) checkPushFrom(tr *Repo) error {
	w, err := Open(tr.root, t.Work, filepath.Join(tr.root, ".cache", "nohooks"))
	if err != nil {
		return refuseTracker(ReasonWorktree, "Run zn from the host, or from a worktree of the tracker.", "%v", err)
	}
	if err := w.checkLocalConfig(); err != nil {
		return refuseTracker(ReasonNotClone, "Remove that setting from the worktree's config, then run the command again.", "%s", strings.TrimPrefix(err.Error(), "host: refusing to run git: "))
	}
	return checkOriginAddress(w)
}

func linkLines() []string {
	var out []string
	for _, n := range engineLinks {
		out = append(out, "/z-nile/"+n)
	}
	return out
}

// plainFolders refuses when a folder that rel names under base, as far as it exists, is a link or not a folder: zn
// never writes through one. Each component is looked at with Lstat, from base down.
func plainFolders(base string, r TrackerReason, next string, rels ...string) error {
	for _, rel := range rels {
		cur := base
		for _, part := range strings.Split(rel, "/") {
			cur = filepath.Join(cur, part)
			st, err := os.Lstat(cur)
			if errors.Is(err, fs.ErrNotExist) {
				break
			}
			if err != nil {
				return refuseTracker(r, "Check that folder's permissions, then run the command again.", "%s cannot be read: %v", cur, err)
			}
			if st.Mode()&fs.ModeSymlink != 0 || !st.IsDir() {
				return refuseTracker(r, next, "%s is a link or not a folder, and zn writes nothing through it", cur)
			}
		}
	}
	return nil
}

// checkOriginAddress refuses a tracker whose origin the git config sends elsewhere for a fetch or a push (an insteadOf or
// pushInsteadOf rule, a pushurl), as git resolves it in the checkout r is opened at. The effective addresses are
// compared by identity with origin's own address and never printed.
func checkOriginAddress(r *Repo) error {
	remotes, err := r.Remotes()
	if err != nil {
		return refuseTracker(ReasonAddress, "Run zn init in the host again with the tracker's address.", "origin's address in %s cannot be read: %v", r.dir, err)
	}
	for _, rm := range remotes {
		if rm.Name != "origin" {
			continue
		}
		if rm.Err != nil || rm.NoIdentity != nil {
			return refuseTracker(ReasonAddress, "Run zn init in the host again with the tracker's address.", "origin's address in %s cannot be used (a credential, an unusual form or no owner and repository)", r.dir)
		}
		if err := verifyOrigin(r, rm.Fetch); err != nil {
			return refuseTracker(ReasonAddress, "Remove that rule or pushurl from your git config or the tracker's, then run the command again.", "in %s, %s", r.dir, strings.TrimPrefix(err.Error(), "host: "))
		}
		return nil
	}
	return refuseTracker(ReasonNotClone, "Run zn init in the host again.", "%s has no remote named origin", r.dir)
}

// checkIgnored asks git whether every path zn owns as a link is ignored in the worktree: a tracked ignore rule that
// un-hides one would let the engine's `git add -A` commit a link that holds the owner's cache path.
func (t *Tracker) checkIgnored() error {
	w := readRepo(t.Work)
	for _, n := range engineLinks {
		p := "z-nile/" + n
		if _, err := w.git("check-ignore", "-q", "--no-index", "--", p); err != nil {
			return refuseTracker(ReasonNotIgnored, "Remove that line in the tracker's main (commit and push), then run the command again.", "git no longer ignores %s in %s: a negation such as !/%s in the tracker's tracked .gitignore shows zn's link", p, t.Work, p)
		}
	}
	return nil
}

// checkZNileFolder refuses a worktree whose z-nile is not a real folder inside it, so no link is written through a link.
func (t *Tracker) checkZNileFolder() error {
	z := filepath.Join(t.Work, "z-nile")
	st, err := os.Lstat(z)
	if err != nil || st.Mode()&fs.ModeSymlink != 0 || !st.IsDir() {
		return refuseTracker(ReasonCodeInTracker, "Restore it as a folder (git -C <that worktree> checkout -- z-nile), then run the command again.", "%s is not a real folder (a link?), and a tracker is data", z)
	}
	real, err := resolve(z)
	work, err2 := resolve(t.Work)
	if err != nil || err2 != nil || real != filepath.Join(work, "z-nile") || !within(t.Dir, real) {
		return refuseTracker(ReasonCodeInTracker, "Restore it as a folder of that worktree, then run the command again.", "%s leads outside the tracker, and a tracker is data", z)
	}
	return nil
}

// isOwnLink says a status entry is one of zn's own engine links (untracked, so shown as "?? z-nile/<name>").
func isOwnLink(entry string) bool {
	if !strings.HasPrefix(entry, "?? z-nile/") {
		return false
	}
	for _, n := range engineLinks {
		if entry[3:] == "z-nile/"+n {
			return true
		}
	}
	return false
}

// foreignChanges are the status entries that are not zn's own links.
func foreignChanges(out string) []string {
	var paths []string
	parts := strings.Split(out, "\x00")
	for i := 0; i < len(parts); i++ {
		e := parts[i]
		if len(e) < 4 || isOwnLink(e) {
			continue
		}
		paths = append(paths, e[3:])
		if e[0] == 'R' || e[0] == 'C' {
			i++
		}
	}
	return paths
}

// standing makes the standing worktree, or moves it to origin/main. It never moves away from a commit that is not on
// origin/main, and never over a change (tracked or untracked) that is not zn's own.
func (t *Tracker) standing(tr *Repo) ([]string, error) {
	abs, err := resolve(t.Work)
	if err != nil || !within(tr.root, abs) {
		return nil, refuseTracker(ReasonWorktree, "Remove what leads there (zn makes the folder itself), then run the command again.", "the standing worktree %s would be outside %s", t.Work, t.Dir)
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
		// a worktree add that was killed leaves a registration whose folder is gone: forget it first
		if _, err := tr.write("worktree", "prune"); err != nil {
			return nil, err
		}
		if _, err := tr.write("worktree", "add", "-q", "--detach", abs, "refs/remotes/origin/main"); err != nil {
			return nil, refuseTracker(ReasonWorktree, "Run git worktree prune in the tracker and remove that folder if it exists, then run the command again.", "making the standing worktree %s failed (%v; git -C %s worktree prune forgets a half-made one)", abs, err, t.Dir)
		}
		return []string{"made the standing worktree " + abs}, nil
	}
	if err != nil {
		return nil, err
	}
	_, common, ok := gitPlaces(abs)
	if st.Mode()&fs.ModeSymlink != 0 || !st.IsDir() || !ok || common != filepath.Join(t.Dir, ".git") {
		return nil, refuseTracker(ReasonWorktree, "Remove it, and zn makes it again on the next run.", "%s is not a worktree of the tracker", abs)
	}
	w, err := Open(tr.root, abs, filepath.Join(tr.root, ".cache", "nohooks"))
	if err != nil {
		return nil, refuseTracker(ReasonWorktree, "Remove it, and zn makes it again on the next run.", "%v", err)
	}
	have, err := w.git("rev-parse", "--verify", "HEAD")
	if err != nil {
		return nil, err
	}
	ahead, err := w.git("rev-list", "--max-count=5", "--abbrev-commit", "refs/remotes/origin/main..HEAD")
	if err != nil {
		return nil, err
	}
	if c := strings.Fields(ahead); len(c) > 0 {
		return nil, refuseTracker(ReasonWorktree, "Push them or move them to a branch, then run the command again.", "%s holds commits that are not on the tracker's main (%s), and zn will not move away from them (git -C %s push origin HEAD:main sends them, after a rebase onto origin/main if it is refused)", abs, strings.Join(c, ", "), abs)
	}
	out, err := w.git("status", "--porcelain=v1", "-z", "--untracked-files=normal")
	if err != nil {
		return nil, err
	}
	if paths := foreignChanges(out); len(paths) > 0 {
		return nil, refuseTracker(ReasonWorktree, "Commit or remove them there, then run the command again.", "%s has files that are not zn's (%s)", abs, listPaths(paths))
	}
	if strings.TrimSpace(have) == want {
		return nil, nil
	}
	if err := w.checkAttributes("refs/remotes/origin/main"); err != nil {
		return nil, err
	}
	if _, err := w.write("checkout", "-q", "--detach", "refs/remotes/origin/main"); err != nil {
		return nil, refuseTracker(ReasonWorktree, "Run the command again; if it fails again, remove that worktree and zn makes it anew.", "moving %s to the tracker's main failed: %v", abs, err)
	}
	return []string{"moved the standing worktree " + abs + " to the tracker's main (" + want[:7] + ")"}, nil
}

var linkSeq atomic.Uint64

// ensureLink makes path a link to target, replacing a link that points elsewhere; a real file or folder there is
// refused, because it is not zn's. The temporary name is unique to this call.
func ensureLink(path, target string) (bool, error) {
	st, err := os.Lstat(path)
	switch {
	case err == nil && st.Mode()&fs.ModeSymlink != 0:
		if got, _ := os.Readlink(path); got == target {
			return false, nil
		}
	case err == nil:
		return false, refuseTracker(ReasonEngineInPlay, "Remove it from the tracker's main (commit and push), then run the command again.", "%s is a real file or folder where zn links its engine, and zn will not replace it", path)
	case !errors.Is(err, fs.ErrNotExist):
		return false, err
	}
	tmp := fmt.Sprintf("%s.zn-link-%d-%d", path, os.Getpid(), linkSeq.Add(1))
	if err := os.Symlink(target, tmp); err != nil {
		return false, err
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return false, err
	}
	return true, nil
}

// Lock is the tracker's command lock: one zn command at a time works in a tracker.
type Lock struct{ f *os.File }

// LockTracker takes the lock in <dir>/.git/zn.lock, trying for up to wait. The message of a failure names the pid of the
// zn that holds it. The lock is an flock on an open file, so it ends with the process that holds it; KeepAcrossExec makes
// it outlive an exec, for the engine that replaces zn. Neither .git nor the lock file may be a link.
func LockTracker(dir string, wait time.Duration) (*Lock, error) {
	if err := plainFolders(dir, ReasonNotClone, "Make it the clone's own folder again, then run the command again.", ".git"); err != nil {
		return nil, err
	}
	path := filepath.Join(dir, ".git", "zn.lock")
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|syscall.O_NOFOLLOW, 0o600)
	if err != nil {
		return nil, fmt.Errorf("tracker: cannot open its lock %s (%w). Remove it if it is a link, then run the command again", path, err)
	}
	tries := int(wait/(100*time.Millisecond)) + 1
	for i := 0; i < tries; i++ {
		if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
			f.Truncate(0)
			fmt.Fprintf(f, "%d\n", os.Getpid())
			return &Lock{f: f}, nil
		}
		if i < tries-1 {
			time.Sleep(100 * time.Millisecond)
		}
	}
	holder := "unknown"
	if b, err := os.ReadFile(path); err == nil && strings.TrimSpace(string(b)) != "" {
		holder = strings.TrimSpace(string(b))
	}
	f.Close()
	return nil, fmt.Errorf("tracker: another zn command (pid %s) is working in the tracker %s: waited %s. Wait for it, or stop it if it is stuck", holder, dir, wait)
}

// KeepAcrossExec lets the lock survive the exec that replaces zn with the engine.
func (l *Lock) KeepAcrossExec() {
	syscall.Syscall(syscall.SYS_FCNTL, l.f.Fd(), syscall.F_SETFD, 0)
}

// Release gives the lock back.
func (l *Lock) Release() {
	if l != nil && l.f != nil {
		l.f.Close()
		l.f = nil
	}
}

// Review-round reasons.
const (
	ReasonCodeInTracker TrackerReason = "tracker-holds-code"        // the tracker's tree or checkout is not data only
	ReasonNotIgnored    TrackerReason = "tracker-unhides-zn-paths"  // a tracked ignore rule shows a zn link
	ReasonAddress       TrackerReason = "tracker-address-rewritten" // the git config sends the tracker's fetch or push elsewhere
)

// ownedNames are the top-level names (compared in lower case) that a tracker never holds: the ones zn owns or that
// would run code or steer a program started in a tracker worktree. zn is the program; .luaurc, .config.luau, .lune and
// lune steer Lune's requires and its script search; AGENTS.md, CLAUDE.md and .claude (its hooks) are what a model CLI
// reads and runs; .models.toml names the model CLIs; scripts holds the hooks .claude names; .cache and .worktree are
// zn's own folders in a checkout, so on disk they are zn's (onDisk false), never the tree's.
var ownedNames = map[string]bool{
	"zn": true, ".luaurc": true, ".config.luau": true, ".lune": true, "lune": true, "agents.md": true, "claude.md": true,
	".claude": true, ".models.toml": true, "scripts": true, ".cache": true, ".worktree": true,
}

// znFoldersOnDisk are the owned names zn itself keeps in a checkout as plain folders.
var znFoldersOnDisk = map[string]bool{".cache": true, ".worktree": true}

// dataFiles are the only files a tracker keeps under z-nile/, each read by one reader of the engine: the registry
// (projects.luau), the id counter and the compaction map (ids.luau). Everything else there is the engine's (engine,
// lib, vendor, templates, roots, affected, bin, skills, specs, check.sh...), which a tracker never holds.
var dataFiles = map[string]bool{"z-nile/projects.toml": true, "z-nile/next": true, "z-nile/compaction.txt": true}

// codeAt says why a tree entry is not data, or "" when it is: a link or a submodule anywhere, an owned top-level name,
// and anything under z-nile/ but the data files. Names compare in lower case, as a case-insensitive disk checks out.
func codeAt(mode, p string) string {
	switch mode {
	case "120000":
		return "a symbolic link"
	case "160000":
		return "a submodule"
	}
	low := strings.ToLower(p)
	first, _, _ := strings.Cut(low, "/")
	switch {
	case ownedNames[first]:
		return "a path zn owns or a program reads as code"
	case first == "z-nile" && !dataFiles[low]:
		return "a file of the engine's folder that is not the registry, the counter or the compaction map"
	}
	return ""
}

// checkData refuses a commit whose tree is not data only (codeAt), naming the first path; what names the commit.
func (r *Repo) checkData(rev, what string) error {
	out, err := r.git("ls-tree", "-r", "-z", "--full-tree", rev)
	if err != nil {
		return err
	}
	for _, ent := range strings.Split(out, "\x00") {
		meta, p, ok := strings.Cut(ent, "\t")
		if !ok {
			continue
		}
		if why := codeAt(strings.Fields(meta)[0], p); why != "" {
			return refuseTracker(ReasonCodeInTracker, "Remove it from the tracker's main (commit and push), then run the command again.", "%s holds %s at `%s` (`git -C %s rm -r -- %s` removes it), and a tracker is data", what, why, p, r.dir, p)
		}
	}
	return nil
}

// checkFiles refuses a checkout that holds on disk, where git may not show it (an ignored file), anything at a name zn
// owns, or under z-nile/ anything but the data files and, in the worktree the engine runs in, zn's own links.
func checkFiles(root string, work bool) error {
	refuse := func(p string) error {
		return refuseTracker(ReasonCodeInTracker, "Remove it, then run the command again.", "%s is at a path zn owns or a program reads as code, and a tracker is data", p)
	}
	ents, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	for _, e := range ents {
		if n := strings.ToLower(e.Name()); ownedNames[n] && !(znFoldersOnDisk[n] && e.IsDir()) {
			return refuse(filepath.Join(root, e.Name()))
		}
	}
	z := filepath.Join(root, "z-nile")
	if st, err := os.Lstat(z); errors.Is(err, fs.ErrNotExist) {
		return nil
	} else if err != nil || st.Mode()&fs.ModeSymlink != 0 || !st.IsDir() {
		return refuse(z)
	}
	ents, err = os.ReadDir(z)
	if err != nil {
		return err
	}
	for _, e := range ents {
		link := false
		for _, n := range engineLinks {
			link = link || e.Name() == n
		}
		switch {
		case dataFiles["z-nile/"+strings.ToLower(e.Name())] && e.Type().IsRegular():
		case work && link && e.Type()&fs.ModeSymlink != 0:
		default:
			return refuse(filepath.Join(z, e.Name()))
		}
	}
	return nil
}

// Round 3 reasons and seams (stubs: the tests come first).
const (
	ReasonAttributes     TrackerReason = "tracker-attributes-run-a-program"
	ReasonGit            TrackerReason = "git-cannot-say"
	ReasonSeparateGitDir TrackerReason = "host-git-directory-elsewhere"
	ReasonHost           TrackerReason = "host-unusual"
	ReasonLock           TrackerReason = "tracker-lock"
)

// afterJudged is a test seam called between the check of origin/main and the checkout (stub).
var afterJudged func()

func shellQuote(s string) string { return s }

// Refresh is Prepare without the fetch (stub).
func (t *Tracker) Refresh(payloadDir string) ([]string, error) { return nil, nil }
