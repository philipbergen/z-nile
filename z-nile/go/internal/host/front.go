package host

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
	"unicode"
	"unicode/utf8"
)

// The front door's reader of the tracker (f0428 step 4). One resolver answers where a host's tracker is and where the
// engine runs, from any folder: the host's own folders, a linked worktree of the host, the tracker's checkout and a
// worktree of the tracker. The engine sees the tracker as a one-project z-nile repository, runs in a worktree of it,
// and publishes to the tracker's origin/main. Nothing here writes into the host.

// TrackerReason names why a host's tracker cannot be used.
type TrackerReason string

// The reasons Locate, Prepare, Refresh and LockTracker refuse, each its own.
const (
	ReasonTrackerLink    TrackerReason = "tracker-not-a-folder"             // .tracker is a link or not a folder
	ReasonNotClone       TrackerReason = "tracker-not-a-clone"              // not the top of its own repository, no origin/main, unsafe config
	ReasonNoRegistry     TrackerReason = "tracker-no-registry"              // z-nile/projects.toml is missing on origin/main
	ReasonDirty          TrackerReason = "tracker-has-changes"              // uncommitted changes of someone else in the tracker's checkout
	ReasonWorktree       TrackerReason = "tracker-worktree-in-the-way"      // the standing worktree is not zn's or holds changes
	ReasonEngineInPlay   TrackerReason = "engine-file-in-the-way"           // a real file where an engine link goes
	ReasonCodeInTracker  TrackerReason = "tracker-holds-code"               // the tracker's tree or checkout is not data only
	ReasonNotIgnored     TrackerReason = "tracker-unhides-zn-paths"         // a tracked ignore rule shows a zn link
	ReasonAddress        TrackerReason = "tracker-address-rewritten"        // the git config sends the tracker's fetch or push elsewhere
	ReasonAttributes     TrackerReason = "tracker-attributes-run-a-program" // a filter=, merge= or diff= attribute in the tracker
	ReasonGit            TrackerReason = "git-cannot-say"                   // git failed (missing, timed out, a damaged repository)
	ReasonSeparateGitDir TrackerReason = "host-git-directory-elsewhere"     // a host with a .tracker whose git directory is not <host>/.git
	ReasonHost           TrackerReason = "host-unusual"                     // the host itself is refused (CheckHost)
	ReasonLock           TrackerReason = "tracker-lock"                     // the tracker's lock cannot be taken
	ReasonShortName      TrackerReason = "tracker-ref-shadows-origin-main"  // another ref is what the name origin/main resolves to
)

// TrackerRefusal is the refusal of a tracker: what is wrong, naming the path, then what to do next. It never holds a
// remote's address or a reason code, and it names every folder by its absolute path. Err is the refusal it wraps (the
// host's own, or git's), for errors.As.
type TrackerRefusal struct {
	Reason TrackerReason
	Detail string
	Next   string // what to do next: the message's last sentence
	Err    error
}

func (e *TrackerRefusal) Error() string {
	return "tracker: " + strings.TrimRight(e.Detail, ". ") + ". " + e.Next
}

// Unwrap is the error the refusal wraps.
func (e *TrackerRefusal) Unwrap() error { return e.Err }

// refuseTracker is every refusal of this file: the reason, what to do next, and the detail.
func refuseTracker(r TrackerReason, next, format string, a ...any) error {
	return &TrackerRefusal{Reason: r, Detail: fmt.Sprintf(format, a...), Next: next}
}

// asRefusal makes every error that leaves the front door a refusal with a next step and no reason code in its text: a
// refusal of this file as it is, the host's own refusal (CheckHost) by its words, and anything else (git's own failure,
// a file that cannot be written) as git-cannot-say.
func asRefusal(err error) error {
	if err == nil {
		return nil
	}
	var r *TrackerRefusal
	if errors.As(err, &r) {
		return err
	}
	var u *UnusualHost
	if errors.As(err, &u) {
		return &TrackerRefusal{Reason: ReasonHost, Detail: u.Detail, Next: "Fix that in the host, then run the command again.", Err: err}
	}
	// git's own words name paths relative to the repository: they are quoted as git's, not as zn's paths
	said := strings.ReplaceAll(terminalSafe(strings.TrimPrefix(err.Error(), "host: ")), "`", "'")
	return &TrackerRefusal{Reason: ReasonGit, Detail: "git failed: `" + said + "`",
		Next: "Run the command again; if it fails again, run git status in the tracker to see why.", Err: err}
}

// Tracker is the tracker of a host: where it is and where the engine runs.
type Tracker struct {
	Host string // the host's main checkout
	Dir  string // <Host>/.tracker, the tracker's main checkout
	Work string // the checkout the engine runs in: the standing worktree, or the tracker worktree the caller is in
}

// HooksDir is the empty folder zn points every git of the engine at for its hooks (core.hooksPath), so no hook runs.
func (t *Tracker) HooksDir() string { return filepath.Join(t.Dir, ".cache", "nohooks") }

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
	return &Repo{dir: dir, reads: withoutRootPath(readEnv(os.Environ(), ""), repoRoots(dir)...)}
}

// gitPlaces is the top level and the common git directory of the repository that holds dir, or ok false when git
// cannot say (no repository, or git failed: the caller tells them apart by what the disk holds).
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

// Locate finds the tracker of the host that cwd belongs to, or nil, nil when none applies: cwd is in no repository and
// no folder above it holds a .tracker, or it is in a repository that has no .tracker beside its .git (a repository like
// this one keeps its tickets inside itself). It only reads, and it judges only what is on disk: the layout, the host
// (CheckHost), the tracker's config, its checkout's HEAD, its files and its changes. origin/main is Prepare's, after its
// fetch, so a bad push fixed upstream never locks zn out. It refuses, naming the cause: a host that tracks .tracker or
// has program-running local config, a .tracker that is a link, not a folder, not the top of a clone of its own, or
// unsafe in its config, a checkout that is not data, one with changes of someone else, a caller in a git directory of
// the tracker or of its host, a tracker worktree outside .tracker/.worktree, a host whose git directory is elsewhere,
// and, when git cannot say where cwd is (git missing, timed out or refusing, a damaged repository), any folder above
// cwd that holds a .tracker.
func Locate(cwd string) (*Tracker, error) {
	t, err := locate(cwd)
	if err != nil {
		return nil, asRefusal(err)
	}
	return t, nil
}

func locate(cwd string) (*Tracker, error) {
	real, err := resolve(cwd)
	if err != nil {
		return nil, nil
	}
	if st, err := os.Stat(real); err != nil || !st.IsDir() {
		return nil, nil
	}
	top, common, ok := gitPlaces(real)
	if !ok {
		for p := real; p != filepath.Dir(p); p = filepath.Dir(p) {
			if filepath.Base(p) == ".git" && filepath.Base(filepath.Dir(p)) == trackerFolder {
				return nil, refuseTracker(ReasonNotClone, "Run zn from a folder of the host or of a worktree of the tracker.", "%s is inside the tracker's git directory %s", real, p)
			}
			if filepath.Base(p) == ".git" && exists(filepath.Join(filepath.Dir(p), trackerFolder)) {
				return nil, refuseTracker(ReasonNotClone, "Run zn from a folder of the host's working tree.", "%s is inside the git directory of the host %s", real, filepath.Dir(p))
			}
			if exists(filepath.Join(p, trackerFolder)) {
				return nil, refuseTracker(ReasonGit, "Run git status in that folder to see why (git missing from PATH, a damaged repository, an owner git does not trust), fix it, then run the command again.", "git cannot say which repository %s is in, and %s holds a .tracker", real, p)
			}
		}
		return nil, nil
	}
	if filepath.Base(common) != ".git" {
		if exists(filepath.Join(top, trackerFolder)) { // a separate git directory or a submodule
			return nil, refuseTracker(ReasonSeparateGitDir, "Run zn from the host's own clone, whose git directory is its .git folder.", "%s has a .tracker but its git directory is not %s, so zn cannot tell where the host's main checkout is", top, filepath.Join(top, ".git"))
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
		if !exists(t.Dir) {
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

// exists says a path exists, a link included (Lstat).
func exists(p string) bool { _, err := os.Lstat(p); return err == nil }

// check is every refusal of the tracker itself that the disk can answer, all reads.
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
		return refuseTracker(ReasonNotClone, "Run zn init in the host, or move the folder away yourself.", "%s is not the top of a clone of a tracker of its own (a plain folder, a worktree, a separate or linked git directory, or one git cannot read)", t.Dir)
	}
	tr, err := openTracker(t.Dir)
	if err != nil {
		return refuseTracker(ReasonNotClone, "Run zn init in the host again.", "%v", err)
	}
	if err := tr.checkLocalConfig(); err != nil {
		return refuseTracker(ReasonNotClone, "Remove that setting from the tracker's config, then run the command again.", "%s", strings.TrimPrefix(err.Error(), "host: refusing to run git: "))
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

// checkRegistry refuses a commit of the tracker that has no registry: the engine reads the roots from nothing else.
func (r *Repo) checkRegistry(rev string) error {
	if _, err := r.git("cat-file", "-e", rev+":"+registryPath); err != nil {
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

// listPaths names up to three paths, each quoted for the shell (a path may hold anything a pusher chose).
func listPaths(paths []string) string {
	var q []string
	for i, p := range paths {
		if i == 3 {
			break
		}
		q = append(q, shellQuote(p))
	}
	if len(paths) > 3 {
		return strings.Join(q, ", ") + fmt.Sprintf(" and %d more", len(paths)-3)
	}
	return strings.Join(q, ", ")
}

// afterJudged is a test seam called after origin/main's commit has been judged and before anything is checked out.
var afterJudged func()

// Prepare makes Work ready for the engine and returns the steps it took (none when nothing was to do). In order: it
// refuses a folder zn writes through (.git, .git/info, .worktree, the standing worktree, .cache) that is a link;
// refuses an origin whose effective fetch or push address the git config rewrites; fetches the tracker's main (a failed
// fetch is a step, not an error: the work goes on from origin/main as last fetched); resolves origin/main once to its
// commit and judges that commit (data only, a registry), which is then the one commit it checks out; makes or moves the
// standing worktree (detached, with none of the user's git config; the tracker's own branch is never moved, and a
// commit that is not on origin/main is never left behind); refuses a linked .cache there and checks the worktree's own
// tree; hides the engine links and the worktree folder in the tracker's exclude file; asks git whether every path zn
// owns is ignored; links the engine from payloadDir, each link confined to a real z-nile folder inside the worktree;
// refuses a file on disk at a path zn owns; keeps the engine's hooks folder empty; and last, just before the engine
// pushes from it, checks the worktree's own config and its effective push address. It writes only inside the tracker.
// The caller holds the tracker's lock (LockTracker) for the whole command.
func (t *Tracker) Prepare(payloadDir string) ([]string, error) {
	steps, err := t.prepare(payloadDir, true)
	return steps, asRefusal(err)
}

// Refresh is Prepare without the fetch: after the engine ran, it judges the main the engine published to (and
// whatever else that main holds by then) and, only when that passes, moves the standing worktree to it.
func (t *Tracker) Refresh(payloadDir string) ([]string, error) {
	steps, err := t.prepare(payloadDir, false)
	return steps, asRefusal(err)
}

func (t *Tracker) prepare(payloadDir string, fetch bool) ([]string, error) {
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
	if err := plainFolders(t.Dir, ReasonWorktree, "Remove the link (zn makes the folder itself), then run the command again.", ".worktree", ".worktree/"+standingName, ".cache", ".cache/nohooks"); err != nil {
		return nil, err
	}
	if err := checkOriginAddress(tr); err != nil {
		return nil, err
	}
	// a clone made before round 4 fetches tags on a plain fetch: zn owns the tracker's config and sets it (the only
	// value of the key zn accepts, so a --tags there is refused before this)
	if v, _ := tr.git("config", "--local", "--get", "remote.origin.tagopt"); strings.TrimSpace(v) != "--no-tags" {
		if _, err := tr.write("config", "--local", "remote.origin.tagopt", "--no-tags"); err != nil {
			return nil, err
		}
		steps = append(steps, "set remote.origin.tagopt=--no-tags in "+t.Dir+" (a tag on the tracker never reaches it)")
	}
	if fetch {
		if err := tr.FetchDefault("origin", "main"); err != nil {
			steps = append(steps, "could not fetch the tracker, working from its origin/main as last fetched")
		}
	}
	want, err := tr.git("rev-parse", "--verify", "-q", "refs/remotes/origin/main^{commit}")
	if err != nil {
		return steps, refuseTracker(ReasonNotClone, "Run zn init in the host again.", "%s has no origin/main", t.Dir)
	}
	want = strings.TrimSpace(want)
	if err := tr.checkData(want, "the tracker's main (origin/main at "+want[:7]+")"); err != nil {
		return steps, err
	}
	if err := tr.checkRegistry(want); err != nil {
		return steps, err
	}
	if err := t.checkShortName(tr, want); err != nil {
		return steps, err
	}
	if afterJudged != nil {
		afterJudged()
	}
	hide := hideFile{root: t.Dir, lines: append([]string{"/.worktree/"}, linkLines()...)}
	if err := hide.check(); err != nil {
		return steps, refuseTracker(ReasonNotClone, "Make it a plain file of the tracker's own git directory, then run the command again.", "%s: %v", hide.path(), err)
	}
	if t.Work == filepath.Join(t.Dir, ".worktree", standingName) {
		s, err := t.standing(tr, want)
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
	if err := os.MkdirAll(t.HooksDir(), 0o755); err != nil {
		return steps, err
	}
	if ents, err := os.ReadDir(t.HooksDir()); err != nil || len(ents) != 0 {
		return steps, refuseTracker(ReasonWorktree, "Empty that folder (zn keeps it empty so no git hook runs), then run the command again.", "%s is not an empty folder", t.HooksDir())
	}
	return steps, t.checkPushFrom(tr)
}

// shadowRefs are the refs git's short name origin/main resolves to before refs/remotes/origin/main (git rev-parse's
// order): the engine names the tracker's main by that short name, so any of them would make it read and build on a
// commit zn never judged. (refs/remotes/origin/main/HEAD, the last in git's order, cannot coexist with the ref itself.)
var shadowRefs = []string{"refs/origin/main", "refs/tags/origin/main", "refs/heads/origin/main"}

// checkShortName refuses a tracker clone in which the name origin/main can mean anything but the tracker's main: a
// file origin/main in the git directory (the common one, or the standing worktree's own) or a ref of shadowRefs, the
// whole of git's resolution order before refs/remotes/origin/main.
func (t *Tracker) checkShortName(tr *Repo, want string) error {
	next := "Delete it in the tracker (git tag -d origin/main for a tag, git branch -D origin/main for a branch, git update-ref -d with its full name otherwise); if the tracker's own repository holds it, it comes back with the next clone, so delete it there too (git push origin :refs/tags/origin/main, or :refs/heads/origin/main), then run the command again."
	for _, f := range []string{filepath.Join(t.Dir, ".git", "origin", "main"), filepath.Join(t.Dir, ".git", "worktrees", standingName, "origin", "main")} {
		if exists(f) {
			return refuseTracker(ReasonShortName, "Remove that file, then run the command again.", "%s is a file git reads as origin/main instead of the tracker's main", f)
		}
	}
	for _, ref := range shadowRefs {
		if _, err := tr.git("show-ref", "--verify", "-q", ref); err == nil {
			return refuseTracker(ReasonShortName, next, "%s holds %s, which git reads as origin/main instead of the tracker's main, so the engine would read and build on a commit zn never judged", t.Dir, ref)
		}
	}
	return nil
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
		return refuseTracker(ReasonCodeInTracker, "Restore it as a folder (git checkout -- z-nile in that worktree), then run the command again.", "%s is not a real folder (a link?), and a tracker is data", z)
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

// standing makes the standing worktree at want (the judged commit of origin/main), or moves it there. It never moves
// away from a commit that is not on want, never over a change (tracked or untracked) that is not zn's own, and takes a
// folder for the worktree only when git says it is the top of a worktree of the tracker. The worktree is made and moved
// with none of the user's git config (the reads environment and its pins), so no filter, hook or attribute of the
// user's runs on the tracker's content.
func (t *Tracker) standing(tr *Repo, want string) ([]string, error) {
	abs, err := resolve(t.Work)
	if err != nil || !within(tr.root, abs) {
		return nil, refuseTracker(ReasonWorktree, "Remove what leads there (zn makes the folder itself), then run the command again.", "the standing worktree %s would be outside %s", t.Work, t.Dir)
	}
	st, err := os.Lstat(abs)
	if errors.Is(err, fs.ErrNotExist) {
		if err := tr.checkAttributes(want); err != nil {
			return nil, refuseTracker(ReasonAttributes, "Remove that attribute from the tracker's main (commit and push), then run the command again.", "%s", strings.TrimPrefix(err.Error(), "host: refusing to create a worktree: "))
		}
		// a worktree add that was killed leaves a registration whose folder is gone: forget it first
		if _, err := tr.write("worktree", "prune"); err != nil {
			return nil, err
		}
		if _, err := tr.checkout("worktree", "add", "-q", "--detach", abs, want); err != nil {
			return nil, refuseTracker(ReasonWorktree, "Run git worktree prune in the tracker and remove that folder if it exists, then run the command again.", "making the standing worktree %s failed (%v)", abs, err)
		}
		if err := tr.rememberStanding(want); err != nil {
			return nil, err
		}
		return []string{"made the standing worktree " + abs}, nil
	}
	if err != nil {
		return nil, err
	}
	top, common, ok := gitPlaces(abs)
	if st.Mode()&fs.ModeSymlink != 0 || !st.IsDir() || !ok || top != abs || common != filepath.Join(t.Dir, ".git") {
		return nil, refuseTracker(ReasonWorktree, "Remove it (it is not zn's), and zn makes the worktree there on the next run.", "%s is not a worktree of the tracker", abs)
	}
	w, err := Open(tr.root, abs, filepath.Join(tr.root, ".cache", "nohooks"))
	if err != nil {
		return nil, refuseTracker(ReasonWorktree, "Remove it, and zn makes it again on the next run.", "%v", err)
	}
	have, err := w.git("rev-parse", "--verify", "HEAD")
	if err != nil {
		return nil, err
	}
	ahead, err := w.git("rev-list", "--max-count=5", "--abbrev-commit", want+"..HEAD")
	if err != nil {
		return nil, err
	}
	// where zn last put the worktree is never the owner's work: after main is rewound upstream, leaving it is safe
	put, _ := tr.git("rev-parse", "--verify", "-q", standingRef)
	if strings.TrimSpace(put) == strings.TrimSpace(have) {
		ahead = ""
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
		return nil, tr.rememberStanding(want)
	}
	if err := w.checkAttributes(want); err != nil {
		return nil, refuseTracker(ReasonAttributes, "Remove that attribute from the tracker's main (commit and push), then run the command again.", "%s", strings.TrimPrefix(err.Error(), "host: refusing to create a worktree: "))
	}
	if _, err := w.checkout("checkout", "-q", "--detach", want); err != nil {
		return nil, refuseTracker(ReasonWorktree, "Run the command again; if it fails again, remove that worktree and zn makes it anew.", "moving %s to the tracker's main failed: %v", abs, err)
	}
	if err := tr.rememberStanding(want); err != nil {
		return nil, err
	}
	return []string{"moved the standing worktree " + abs + " to the tracker's main (" + want[:7] + ")"}, nil
}

// standingRef is where zn records, in the tracker clone, the commit it last put the standing worktree at. A pusher
// cannot write it (zn fetches only refs/remotes/origin/main).
const standingRef = "refs/zn/standing"

// rememberStanding records want as where the standing worktree is, when it is not recorded already.
func (r *Repo) rememberStanding(want string) error {
	if got, err := r.git("rev-parse", "--verify", "-q", standingRef); err == nil && strings.TrimSpace(got) == want {
		return nil
	}
	_, err := r.write("update-ref", standingRef, want)
	return err
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
// zn that holds it. The lock is an flock on a file opened close-on-exec: only the zn that took it holds it, never a
// program it starts, and it ends with that zn. Neither .git nor the lock file may be a link.
func LockTracker(dir string, wait time.Duration) (*Lock, error) {
	l, err := lockTracker(dir, wait)
	return l, asRefusal(err)
}

func lockTracker(dir string, wait time.Duration) (*Lock, error) {
	if err := plainFolders(dir, ReasonLock, "Make it the clone's own folder again, then run the command again.", ".git"); err != nil {
		return nil, err
	}
	path := filepath.Join(dir, ".git", "zn.lock")
	f, err := os.OpenFile(path, os.O_RDWR|os.O_CREATE|syscall.O_NOFOLLOW, 0o600)
	if err != nil {
		return nil, refuseTracker(ReasonLock, "Remove it if it is a link, then run the command again.", "zn cannot open its lock %s (%v)", path, err)
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
	if stoppedProcess(holder) {
		return nil, refuseTracker(ReasonLock, "Bring it back (fg in its terminal, or kill -CONT with its pid), or end it, then run the command again.", "another zn command (pid %s) is working in the tracker %s and is stopped (Ctrl-Z): it holds the lock while stopped", holder, dir)
	}
	return nil, refuseTracker(ReasonLock, "Wait for it, or stop it if it is stuck.", "another zn command (pid %s) is working in the tracker %s: waited %s", terminalSafe(holder), dir, wait)
}

// stoppedProcess says the process with that pid is stopped (ps reports state T), asked of ps, bounded.
func stoppedProcess(pid string) bool {
	if _, err := strconv.Atoi(pid); err != nil {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "/bin/ps", "-o", "stat=", "-p", pid).Output()
	return err == nil && strings.HasPrefix(strings.TrimSpace(string(out)), "T")
}

// Release gives the lock back.
func (l *Lock) Release() {
	if l != nil && l.f != nil {
		l.f.Close()
		l.f = nil
	}
}

// ownedNames are the top-level names that a tracker never holds: the ones zn owns or that would run code or steer a
// program started in a tracker worktree. zn is the program; .luaurc, .config.luau, .lune and lune steer Lune's requires
// and its script search; .models.toml names the model CLIs; scripts holds the hooks .claude names; .cache and
// .worktree are zn's own folders in a checkout, so on disk they are zn's (znFoldersOnDisk), never the tree's. The names
// a model CLI reads (anywhereNames) are refused at every depth.
var ownedNames = []string{"zn", ".luaurc", ".config.luau", ".lune", "lune", ".models.toml", "scripts", ".cache", ".worktree"}

// anywhereNames are refused at any depth of the tree: what a model CLI started in a folder reads and runs.
var anywhereNames = []string{"agents.md", "claude.md", ".claude"}

// znFoldersOnDisk are the owned names zn itself keeps in a checkout as plain folders.
var znFoldersOnDisk = map[string]bool{".cache": true, ".worktree": true}

// dataFiles are the only files a tracker keeps under z-nile/, each read by one reader of the engine: the registry
// (projects.luau), the id counter and the compaction map (ids.luau). Everything else there is the engine's (engine,
// lib, vendor, templates, roots, affected, bin, skills, specs, check.sh...), which a tracker never holds.
var dataFiles = map[string]bool{"z-nile/projects.toml": true, "z-nile/next": true, "z-nile/compaction.txt": true}

// plainName is a name as a disk or a reader may take it: zero-width and combining marks dropped, fullwidth ASCII made
// ASCII. Case is left for EqualFold, which folds by Unicode (a long s is an s, the Kelvin sign a k).
func plainName(name string) []rune {
	var out []rune
	for _, r := range name {
		switch {
		case unicode.In(r, unicode.Mn, unicode.Me, unicode.Cf):
			continue
		case r >= 0xFF01 && r <= 0xFF5E:
			r -= 0xFEE0
		}
		out = append(out, r)
	}
	return out
}

// sameName says a name is owned, or a look-alike of it: equal once plain and folded, or of the same length with every
// ASCII letter matching and at most half of the letters replaced by other characters (a Cyrillic A in AGENTS.md).
func sameName(name, owned string) bool {
	rs, o := plainName(name), []rune(owned)
	if strings.EqualFold(string(rs), owned) {
		return true
	}
	if len(rs) != len(o) {
		return false
	}
	ascii := 0
	for i := range o {
		if rs[i] < utf8.RuneSelf {
			if !strings.EqualFold(string(rs[i]), string(o[i])) {
				return false
			}
			ascii++
		}
	}
	return ascii < len(o) && 2*ascii >= len(o)
}

func ownedAt(name string, names []string) bool {
	for _, n := range names {
		if sameName(name, n) {
			return true
		}
	}
	return false
}

// plainASCII says a name holds only printable ASCII (space to tilde): the top-level names of a tracker are its project
// folders (the registry's grammar), README.md, .gitignore and z-nile, so nothing else is needed there, and no disk's
// folding (a ligature, a Kelvin sign) can turn such a name into an owned one.
func plainASCII(name string) bool {
	for i := 0; i < len(name); i++ {
		if name[i] < 0x20 || name[i] > 0x7e {
			return false
		}
	}
	return true
}

// codeAt says why a tree entry is not data, or "" when it is: a link or a submodule anywhere, an owned top-level name,
// a name a model CLI reads at any depth, and anything under z-nile/ but the data files. Names compare as a
// case-insensitive disk or a careless reader takes them (sameName).
func codeAt(mode, p string) string {
	switch mode {
	case "120000":
		return "a symbolic link"
	case "160000":
		return "a submodule"
	}
	parts := strings.Split(p, "/")
	for _, part := range parts {
		if ownedAt(part, anywhereNames) {
			return "a file a model CLI reads as instructions"
		}
	}
	first := parts[0]
	switch {
	case !plainASCII(first):
		return "a top-level name that is not plain printable ASCII (a disk may open it as a name zn owns)"
	case ownedAt(first, ownedNames):
		return "a path zn owns or a program reads as code"
	case strings.EqualFold(first, "z-nile"):
		if !dataFiles[strings.ToLower(p)] {
			return "a file of the engine's folder that is not the registry, the counter or the compaction map"
		}
	case sameName(first, "z-nile"):
		return "a look-alike of the engine's folder"
	}
	return ""
}

// checkData refuses a commit whose tree is not data only (codeAt), naming the first path quoted for the shell; what
// names the commit.
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
			return refuseTracker(ReasonCodeInTracker, "Remove it from the tracker's main (in a clone of the tracker on main: git rm -r that path, commit and push), then run the command again.", "%s holds %s at %s, and a tracker is data", what, why, shellQuote(p))
		}
	}
	return nil
}

// checkFiles refuses a checkout that holds on disk, where git may not show it (an ignored file), anything at a name zn
// owns or a model CLI reads (at the top), or under z-nile/ anything but the data files and, in the worktree the engine
// runs in, zn's own links.
func checkFiles(root string, work bool) error {
	refuse := func(p string) error {
		return refuseTracker(ReasonCodeInTracker, "Remove it, then run the command again.", "%s is at a path zn owns or a program reads as code, and a tracker is data", shellQuote(p))
	}
	ents, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	for _, e := range ents {
		n := e.Name()
		zn := znFoldersOnDisk[strings.ToLower(n)] && e.IsDir()
		if !plainASCII(n) || ownedAt(n, anywhereNames) || ownedAt(n, ownedNames) && !zn || !strings.EqualFold(n, "z-nile") && sameName(n, "z-nile") {
			return refuse(filepath.Join(root, n))
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

// hiddenRunes are format and separator characters that change how a terminal shows text without being seen: the bidi
// embeddings, overrides and isolates and their marks, and the line and paragraph separators. (Not all of Cf: an emoji's
// zero-width joiner must keep working.)
func hiddenRune(r rune) bool {
	return r >= 0x202a && r <= 0x202e || r >= 0x2066 && r <= 0x2069 || r == 0x200e || r == 0x200f || r == 0x061c || r == 0x2028 || r == 0x2029
}

// shellQuote is s as one word for a POSIX shell (and zsh), so a path the tracker holds can be pasted into a command
// safely and printed without its bytes reaching the terminal: plain when it holds only safe characters, in single
// quotes otherwise, and in $'...' with every control byte, DEL, C1 control and invalid byte escaped when it holds any.
func shellQuote(s string) string {
	if s == "" {
		return "''"
	}
	plain, control := true, false
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		switch {
		case r == utf8.RuneError && size == 1, r < 0x20, r == 0x7f, r >= 0x80 && r <= 0x9f, hiddenRune(r):
			control = true
		case !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("_./-@%+=:,", r)):
			plain = false
		}
		i += size
	}
	if !control {
		if plain {
			return s
		}
		return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
	}
	var b strings.Builder
	b.WriteString("$'")
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		switch {
		case r == utf8.RuneError && size == 1:
			fmt.Fprintf(&b, `\x%02x`, s[i])
		case r == '\n':
			b.WriteString(`\n`)
		case r == '\t':
			b.WriteString(`\t`)
		case r == '\r':
			b.WriteString(`\r`)
		case r == '\\' || r == '\'':
			b.WriteByte('\\')
			b.WriteRune(r)
		case r < 0x20 || r == 0x7f:
			fmt.Fprintf(&b, `\x%02x`, r)
		case r >= 0x80 && r <= 0x9f, hiddenRune(r):
			fmt.Fprintf(&b, `\u%04x`, r)
		default:
			b.WriteRune(r)
		}
		i += size
	}
	b.WriteString("'")
	return b.String()
}

// TerminalSafe is terminalSafe, for the front door's filter of what the engine prints.
func TerminalSafe(s string) string { return terminalSafe(s) }

// terminalSafe is a text with every control byte but none of its meaning: C0 controls (newline and tab included), DEL,
// C1 controls and invalid bytes are written as \xHH or \uHHHH, so a string the tracker supplied cannot move the
// cursor, clear the screen or set the window's title.
func terminalSafe(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); {
		r, size := utf8.DecodeRuneInString(s[i:])
		switch {
		case r == utf8.RuneError && size == 1:
			fmt.Fprintf(&b, `\x%02x`, s[i])
		case r < 0x20 || r == 0x7f:
			fmt.Fprintf(&b, `\x%02x`, r)
		case r >= 0x80 && r <= 0x9f, hiddenRune(r):
			fmt.Fprintf(&b, `\u%04x`, r)
		default:
			b.WriteRune(r)
		}
		i += size
	}
	return b.String()
}
