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
	if !ok {
		for p := real; p != filepath.Dir(p); p = filepath.Dir(p) { // inside a git directory of a host that has a tracker
			if _, err := os.Lstat(filepath.Join(filepath.Dir(p), trackerFolder)); filepath.Base(p) == ".git" && err == nil {
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
	if err := tr.checkData("refs/remotes/origin/main"); err != nil {
		return err
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

// Prepare makes Work ready for the engine and returns the steps it took (none when nothing was to do). In order: it
// refuses an origin whose effective fetch or push address the git config rewrites; fetches the tracker's main (a failed
// fetch is a step, not an error: the work goes on from origin/main as last fetched); refuses a tracker tree that holds
// code; makes or moves the standing worktree (detached; the tracker's own branch is never moved, and a commit that is not
// on origin/main is never left behind); checks the worktree's own tree; hides the engine links and the worktree folder in
// the tracker's exclude file; asks git whether every path zn owns is ignored; and links the engine from payloadDir, each
// link confined to a real z-nile folder inside the worktree. It writes only inside the tracker. The caller holds the
// tracker's lock (LockTracker) for the whole command.
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
	if err := checkOriginAddress(tr); err != nil {
		return nil, err
	}
	if err := tr.FetchDefault("origin", "main"); err != nil {
		steps = append(steps, "could not fetch the tracker, working from its origin/main as last fetched")
	}
	if err := tr.checkData("refs/remotes/origin/main"); err != nil {
		return nil, err
	}
	if err := tr.checkRegistry(); err != nil {
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
	head, err := readRepo(t.Work).git("rev-parse", "--verify", "HEAD^{commit}")
	if err != nil {
		return steps, refuseTracker(ReasonWorktree, "%q is not a worktree of the tracker", t.Work)
	}
	if err := tr.checkData(strings.TrimSpace(head)); err != nil {
		return steps, err
	}
	added, err := hide.apply()
	if err != nil {
		return steps, err
	}
	if len(added) > 0 {
		steps = append(steps, "hid the engine links in the tracker's .git/info/exclude")
	}
	if err := t.checkIgnored(); err != nil {
		return steps, err
	}
	if err := t.checkZNileFolder(); err != nil {
		return steps, err
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

// checkOriginAddress refuses a tracker whose origin the git config sends elsewhere for a fetch or a push (an insteadOf or
// pushInsteadOf rule, a pushurl). The effective addresses are compared by identity with origin's own address and never
// printed.
func checkOriginAddress(tr *Repo) error {
	remotes, err := tr.Remotes()
	if err != nil {
		return refuseTracker(ReasonAddress, "origin cannot be read: %v", err)
	}
	for _, rm := range remotes {
		if rm.Name != "origin" {
			continue
		}
		if rm.Err != nil || rm.NoIdentity != nil {
			return refuseTracker(ReasonAddress, "origin's address cannot be used (a credential, an unusual form or no owner and repository): run zn init again with the tracker's address")
		}
		if err := verifyOrigin(tr, rm.Fetch); err != nil {
			return refuseTracker(ReasonAddress, "%s", strings.TrimPrefix(err.Error(), "host: "))
		}
		return nil
	}
	return refuseTracker(ReasonNotClone, ".tracker has no remote named origin: run zn init in the host again")
}

// checkIgnored asks git whether every path zn owns as a link is ignored in the worktree: a tracked ignore rule that
// un-hides one would let the engine's `git add -A` commit a link that holds the owner's cache path.
func (t *Tracker) checkIgnored() error {
	w := readRepo(t.Work)
	for _, n := range engineLinks {
		p := "z-nile/" + n
		if _, err := w.git("check-ignore", "-q", "--no-index", "--", p); err != nil {
			return refuseTracker(ReasonNotIgnored, "git no longer ignores %s in the tracker: a negation such as !/%s in the tracker's tracked .gitignore shows zn's link. Remove that line in the tracker's main (commit and push), then run the command again", p, p)
		}
	}
	return nil
}

// checkZNileFolder refuses a worktree whose z-nile is not a real folder inside it, so no link is written through a link.
func (t *Tracker) checkZNileFolder() error {
	z := filepath.Join(t.Work, "z-nile")
	st, err := os.Lstat(z)
	if err != nil || st.Mode()&fs.ModeSymlink != 0 || !st.IsDir() {
		return refuseTracker(ReasonCodeInTracker, "z-nile in %s is not a real folder (a link?): a tracker is data. Restore it as a folder (git -C %s checkout -- z-nile), then run the command again", t.Work, t.Work)
	}
	real, err := resolve(z)
	work, err2 := resolve(t.Work)
	if err != nil || err2 != nil || real != filepath.Join(work, "z-nile") || !within(t.Dir, real) {
		return refuseTracker(ReasonCodeInTracker, "z-nile in %s leads outside the tracker: a tracker is data", t.Work)
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
		// a worktree add that was killed leaves a registration whose folder is gone: forget it first
		if _, err := tr.write("worktree", "prune"); err != nil {
			return nil, err
		}
		if _, err := tr.write("worktree", "add", "-q", "--detach", abs, "refs/remotes/origin/main"); err != nil {
			return nil, refuseTracker(ReasonWorktree, "making .tracker/.worktree/%s failed (%v): run git -C .tracker worktree prune, remove .tracker/.worktree/%s if it exists, then run the command again", standingName, err, standingName)
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
	ahead, err := w.git("rev-list", "--max-count=5", "--abbrev-commit", "refs/remotes/origin/main..HEAD")
	if err != nil {
		return nil, err
	}
	if c := strings.Fields(ahead); len(c) > 0 {
		return nil, refuseTracker(ReasonWorktree, ".tracker/.worktree/%s holds commits that are not on the tracker's main (%s): zn will not move away from them. Push them (git -C .tracker/.worktree/%s push origin HEAD:main, after a rebase onto origin/main if it is refused) or move them to a branch, then run the command again", standingName, strings.Join(c, ", "), standingName)
	}
	out, err := w.git("status", "--porcelain=v1", "-z", "--untracked-files=normal")
	if err != nil {
		return nil, err
	}
	if paths := foreignChanges(out); len(paths) > 0 {
		return nil, refuseTracker(ReasonWorktree, ".tracker/.worktree/%s has files that are not zn's (%s): commit or remove them there, then run the command again", standingName, listPaths(paths))
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
		return false, refuseTracker(ReasonEngineInPlay, "the tracker holds a real z-nile/%s where zn links its engine: zn will not replace it. Remove it from the tracker's main (commit and push), then run the command again", filepath.Base(path))
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
// it outlive an exec, for the engine that replaces zn.
func LockTracker(dir string, wait time.Duration) (*Lock, error) {
	path := filepath.Join(dir, ".git", "zn.lock")
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|syscall.O_NOFOLLOW, 0o600)
	if err != nil {
		return nil, fmt.Errorf("tracker: cannot open its lock %s: %w", filepath.Join(".tracker", ".git", "zn.lock"), err)
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
	return nil, fmt.Errorf("tracker: another zn command (pid %s) is working in the tracker: waited %s. Wait for it, or stop it if it is stuck", holder, wait)
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
	ReasonCodeInTracker TrackerReason = "tracker-holds-code"        // a path zn owns in the worktree is in the tracker's tree
	ReasonNotIgnored    TrackerReason = "tracker-unhides-zn-paths"  // a tracked ignore rule shows a zn link
	ReasonAddress       TrackerReason = "tracker-address-rewritten" // the git config sends the tracker's fetch or push elsewhere
)

// ownedPaths are the paths zn owns in a tracker worktree, or that would run code or steer a program started there
// (an AGENTS.md or .claude a model CLI reads, a .luaurc that redefines requires, a check.sh, a zn wrapper). A tracker is
// data: its tree holds none of them, at or under.
var ownedPaths = []string{
	"z-nile/engine", "z-nile/lib", "z-nile/vendor", "z-nile/templates", "z-nile/roots.luau", "z-nile/affected.luau",
	"z-nile/bin", "z-nile/specs.luau", "z-nile/check.sh", "zn", ".luaurc", "AGENTS.md", "CLAUDE.md", ".claude", "z-nile/skills",
}

// checkData refuses a commit whose tree holds code: an entry at or under a path zn owns, or a z-nile that is not a plain
// folder (a link out of the tracker).
func (r *Repo) checkData(rev string) error {
	args := []string{"ls-tree", "-r", "-z", "--name-only", rev, "--"}
	for _, p := range ownedPaths {
		args = append(args, ":(literal)"+p)
	}
	out, err := r.git(args...)
	if err != nil {
		return err
	}
	if p, _, _ := strings.Cut(out, "\x00"); p != "" {
		return refuseTracker(ReasonCodeInTracker, "the tracker holds code at %s; a tracker is data. Remove it from the tracker's main (in a clone of the tracker: git rm -r %s, commit and push), then run the command again", p, p)
	}
	if mode, err := r.git("ls-tree", rev, "--", ":(literal)z-nile"); err == nil && strings.TrimSpace(mode) != "" && !strings.HasPrefix(mode, "040000 tree") {
		return refuseTracker(ReasonCodeInTracker, "the tracker's z-nile is not a plain folder (a link?); a tracker is data. Replace it with a folder in the tracker's main, commit and push, then run the command again")
	}
	return nil
}
