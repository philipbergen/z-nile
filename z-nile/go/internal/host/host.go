// Package host does the git work zn does inside a host repository it does not own (f0428 step 1): a snapshot of the
// host's refs, config and .git files that can be compared, and the one designed fetch-and-worktree write.
//
// Confinement: the caller names a root, which is the host's main checkout. Open resolves the repository git itself
// finds (top level, git directory, common git directory) and refuses unless all three are the root's own, so a folder
// inside the root can never lead git to a repository outside it.
//
// Two environments, both built from an allowlist: reads (snapshot, checks) pin the user's global and system git config
// to nothing; writes (fetch, worktree add) use them, because credentials, proxies and url rewrites live there, and pin
// everything that could make a write reach further or run code (no hook runs: core.hooksPath is an empty folder).
package host

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// gitTimeout bounds every git call.
const gitTimeout = 2 * time.Minute

// Repo is a host repository (its main checkout or one of its worktrees) with the root every path must stay under.
type Repo struct {
	dir      string // resolved checkout folder
	root     string // resolved allowed root: the host's main checkout
	gitDir   string // resolved common git directory, <root>/.git
	hooksDir string // resolved empty folder git is pointed at for hooks
	reads    []string
	writes   []string
	// skipConfigCheck is a test seam that lets a test see the command-line pins win without the allowlist in front.
	skipConfigCheck bool
}

// Open returns the repository at dir, which must be the repository whose main checkout is root. hooksDir is an empty
// folder inside root (created when missing) that stops every hook from running during zn's own git writes.
func Open(root, dir, hooksDir string) (*Repo, error) {
	r := &Repo{}
	var err error
	if r.root, err = resolve(root); err != nil {
		return nil, fmt.Errorf("host: allowed root %q: %w", root, err)
	}
	if filepath.Dir(r.root) == r.root {
		return nil, fmt.Errorf("host: the allowed root %q is the filesystem root", root)
	}
	if r.dir, err = resolve(dir); err != nil {
		return nil, fmt.Errorf("host: %q: %w", dir, err)
	}
	if !within(r.root, r.dir) {
		return nil, fmt.Errorf("host: %q is not inside the allowed root %q", dir, root)
	}
	if r.hooksDir, err = resolve(hooksDir); err != nil {
		return nil, fmt.Errorf("host: hooks folder %q: %w", hooksDir, err)
	}
	cache, err := resolve(filepath.Join(r.root, ".cache"))
	if err != nil || !within(r.root, r.hooksDir) || !within(cache, r.hooksDir) || r.hooksDir == cache {
		return nil, fmt.Errorf("host: hooks folder %q is not inside %q (the host's ignored .cache folder)", hooksDir, filepath.Join(r.root, ".cache"))
	}
	ceiling := filepath.Dir(r.root) // git may look at the root's own .git and never above the root
	// no PATH entry inside the repository, nor inside the host when the repository is its tracker
	roots := []string{r.root}
	if filepath.Base(r.root) == ".tracker" {
		roots = append(roots, filepath.Dir(r.root))
	}
	r.reads = withoutRootPath(readEnv(os.Environ(), ceiling), roots...)
	r.writes = withoutRootPath(writeEnv(os.Environ(), ceiling), roots...)
	out, err := r.git("rev-parse", "--path-format=absolute", "--show-toplevel", "--absolute-git-dir", "--git-common-dir")
	if err != nil {
		return nil, fmt.Errorf("host: %q is not a repository inside the allowed root %q: %w", dir, root, err)
	}
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if len(lines) != 3 {
		return nil, fmt.Errorf("host: unreadable repository paths %q", out)
	}
	top, gitdir, common := lines[0], lines[1], lines[2]
	for _, p := range []struct{ what, path string }{{"top level", top}, {"git directory", gitdir}} {
		real, err := resolve(p.path)
		if err != nil || !within(r.root, real) {
			return nil, fmt.Errorf("host: the %s %q git resolves for %q is not inside the allowed root %q", p.what, p.path, dir, root)
		}
	}
	if r.gitDir, err = resolve(common); err != nil {
		return nil, err
	}
	want, err := resolve(filepath.Join(r.root, ".git"))
	if err != nil || r.gitDir != want {
		return nil, fmt.Errorf("host: the common git directory %q is not %q: the root must be the host's main checkout", common, filepath.Join(r.root, ".git"))
	}
	return r, nil
}

// Dir is the checkout folder the repository was opened at.
func (r *Repo) Dir() string { return r.dir }

// CleanPath is a PATH value with only the entries a program may be looked up in: absolute (an empty entry, ./bin or
// bin would be looked up from whatever folder git or the engine works in, which may be the tracker's, someone else's
// content) and inside none of roots (the host's or the tracker's folders). It is the one PATH cleaner, for zn's own git
// and for the engine.
//
// Inside is decided by identity, not by spelling (review-004 F5): the entry is resolved through its longest existing
// prefix (resolve), and it is inside a root when the entry or any of its ancestors is the same file as the root
// (os.SameFile), so another case of the folder on a case-insensitive disk, the data volume's alias of a folder and a
// tail that does not exist yet behind a linked prefix are all inside.
func CleanPath(v string, roots ...string) string {
	var rootInfo []os.FileInfo
	for _, r := range roots {
		if st, err := os.Stat(r); r != "" && err == nil {
			rootInfo = append(rootInfo, st)
		}
	}
	var keep []string
	for _, e := range strings.Split(v, ":") {
		if !filepath.IsAbs(e) {
			continue
		}
		lexical := false // a root that does not exist (yet) is still compared by its spelling
		for _, r := range roots {
			lexical = lexical || r != "" && (within(filepath.Clean(r), filepath.Clean(e)) || within(resolvedOr(r), resolvedOr(e)))
		}
		if !lexical && !insideAny(e, rootInfo) {
			keep = append(keep, e)
		}
	}
	return strings.Join(keep, ":")
}

// insideAny says a path, as resolved, is one of roots or below one: the path and each of its ancestors are compared
// with each root by identity.
func insideAny(p string, roots []os.FileInfo) bool {
	if len(roots) == 0 {
		return false
	}
	for _, q := range []string{filepath.Clean(p), resolvedOr(p)} {
		for a := q; ; a = filepath.Dir(a) {
			if st, err := os.Stat(a); err == nil {
				for _, r := range roots {
					if os.SameFile(st, r) {
						return true
					}
				}
			}
			if a == filepath.Dir(a) {
				break
			}
		}
	}
	return false
}

func resolvedOr(p string) string {
	if r, err := resolve(p); err == nil {
		return r
	}
	return filepath.Clean(p)
}

// repoRoots are the folders whose content someone else may write that a git run in dir works under: dir and every
// folder above it that holds a .git or a .tracker (the repository, and a host above its tracker).
func repoRoots(dir string) []string {
	roots := []string{dir}
	for p := dir; p != filepath.Dir(p); p = filepath.Dir(p) {
		if exists(filepath.Join(p, ".git")) || exists(filepath.Join(p, ".tracker")) {
			roots = append(roots, p)
		}
	}
	return roots
}

// withoutRootPath is env with its PATH cleaned of every entry inside one of roots (CleanPath).
func withoutRootPath(env []string, roots ...string) []string {
	out := make([]string, 0, len(env))
	for _, kv := range env {
		if v, ok := strings.CutPrefix(kv, "PATH="); ok {
			kv = "PATH=" + CleanPath(v, roots...)
		}
		out = append(out, kv)
	}
	return out
}

// lookGit is the git program the PATH of env names (its first executable git), so the git zn runs is chosen by the
// cleaned PATH, never by zn's own process PATH, and never a bare name a lookup elsewhere would resolve.
func lookGit(env []string) (string, error) {
	for _, kv := range env {
		if v, ok := strings.CutPrefix(kv, "PATH="); ok {
			for _, d := range strings.Split(v, ":") {
				p := filepath.Join(d, "git")
				if st, err := os.Stat(p); filepath.IsAbs(d) && err == nil && st.Mode().IsRegular() && st.Mode()&0o111 != 0 {
					return p, nil
				}
			}
		}
	}
	return "", errors.New("host: no git on PATH outside the repository (zn never runs a git found inside the host or its tracker): put the folder of your git on PATH")
}

// allowedEnv is the allowlist both environments are built from. PATH is cleaned (CleanPath). Proxy variables, the
// session's runtime folder and its message bus stay out (step 2's rule): a proxy decides where git connects, which the
// address check cannot see.
func allowedEnv(in []string) []string {
	var out []string
	for _, kv := range in {
		k, v, _ := strings.Cut(kv, "=")
		switch k {
		case "PATH":
			out = append(out, "PATH="+CleanPath(v))
		case "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "SSH_AUTH_SOCK", "XDG_CONFIG_HOME":
			out = append(out, kv)
		default:
			if strings.HasPrefix(k, "LC_") {
				out = append(out, kv)
			}
		}
	}
	return out
}

func gitPins(env []string, ceiling string) []string {
	env = append(env, "GIT_TERMINAL_PROMPT=0", "GIT_OPTIONAL_LOCKS=0")
	if ceiling != "" {
		env = append(env, "GIT_CEILING_DIRECTORIES="+ceiling)
	}
	return env
}

// readEnv is the environment of reads: the user's global and system git config are pinned to nothing.
func readEnv(in []string, ceiling string) []string {
	return gitPins(append(allowedEnv(in), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null", "GIT_CONFIG_NOSYSTEM=1"), ceiling)
}

// writeEnv is the environment of writes: the user's global and system git config apply (credentials, proxies, url
// rewrites); the command line pins what must not follow from them.
func writeEnv(in []string, ceiling string) []string {
	return gitPins(allowedEnv(in), ceiling)
}

// readPins stop what a -c can stop on every read: a read that touches the index starts the host's own
// core.fsmonitor program, and a hook or a transport helper must never run during a read (the lesson
// repo-local-git-config-can-run-a-program). Keys a -c cannot stop are refused by checkLocalConfig before any write.
var readPins = []string{
	"-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "-c", "protocol.ext.allow=never", "-c", "protocol.fd.allow=never",
	"-c", "gc.auto=0", "-c", "maintenance.auto=false",
}

// git runs one read-only git command in the repository and returns its stdout.
func (r *Repo) git(args ...string) (string, error) {
	return r.exec(r.reads, append(append([]string{}, readPins...), args...))
}

// readGit runs a read-only git command (the tests use it to see what a read sees).
func (r *Repo) readGit(args ...string) (string, error) { return r.git(args...) }

// write runs one git command that writes: with the user's config, every pin of the design, and no hook.
func (r *Repo) write(args ...string) (string, error) {
	if err := r.checkLocalConfig(); err != nil {
		return "", err
	}
	if err := os.MkdirAll(r.hooksDir, 0o755); err != nil {
		return "", err
	}
	if ents, err := os.ReadDir(r.hooksDir); err != nil || len(ents) != 0 {
		return "", fmt.Errorf("host: hooks folder %q is not empty (%v): refusing to run git", r.hooksDir, err)
	}
	pins := []string{
		"-c", "core.hooksPath=" + r.hooksDir, "-c", "core.fsmonitor=false",
		"-c", "gc.auto=0", "-c", "maintenance.auto=false", "-c", "protocol.ext.allow=never", "-c", "protocol.fd.allow=never",
		"-c", "fetch.prune=false", "-c", "fetch.pruneTags=false", "-c", "submodule.recurse=false",
	}
	return r.exec(r.writes, append(pins, args...))
}

func (r *Repo) exec(env, args []string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), gitTimeout)
	defer cancel()
	gitPath, err := lookGit(env)
	if err != nil {
		return "", err
	}
	cmd := exec.CommandContext(ctx, gitPath, append([]string{"-C", r.dir}, args...)...)
	cmd.Env = env
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("host: git %s: %w: %s", scrubURLs(strings.Join(args, " ")), err, scrubURLs(strings.TrimSpace(stderr.String())))
	}
	return stdout.String(), nil
}

// resolve makes p absolute and resolves symlinks in its longest existing prefix, so a path that does not exist yet
// still compares by its real place.
func resolve(p string) (string, error) {
	abs, err := filepath.Abs(p)
	if err != nil {
		return "", err
	}
	rest := ""
	cur := abs
	for {
		if real, err := filepath.EvalSymlinks(cur); err == nil {
			return filepath.Join(real, rest), nil
		} else if !errors.Is(err, fs.ErrNotExist) {
			return "", err
		}
		parent := filepath.Dir(cur)
		if parent == cur {
			return abs, nil
		}
		rest = filepath.Join(filepath.Base(cur), rest)
		cur = parent
	}
}

// within reports whether p is root or below it. The comparison is by path segments and case-sensitive: on a
// case-insensitive filesystem a differently-cased spelling is refused, so it fails closed.
func within(root, p string) bool {
	rel, err := filepath.Rel(root, p)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

// Kind says what a Change is about.
type Kind string

// The kinds of change a snapshot diff reports.
const (
	KindRef    Kind = "ref"    // a ref under refs/, loose or packed
	KindConfig Kind = "config" // a key of the repository's local config
	KindFile   Kind = "file"   // a file, link or empty folder of the common git directory, object payloads aside
)

// implicitValue stands for a config key written without a value (git reads it as true), unlike an empty value.
const implicitValue = "\x00"

// Snapshot is the host's refs, local config and git-directory files at one moment.
type Snapshot struct {
	Refs   map[string]string // ref name -> object id (or "-> target" for a symbolic ref), loose and packed alike
	Config map[string]string // config key -> its values joined by newlines (implicitValue for a bare key)
	Files  map[string]string // path (with a trailing / for an empty folder) -> mode and content hash, or "link -> target"
}

// Change is one difference between two snapshots.
type Change struct {
	Kind Kind
	Name string
	Old  string
	New  string
	// HadOld and HasNew say whether the item existed before and after (an empty value is not an absent item).
	HadOld, HasNew bool
}

func show(v string) string {
	if v == implicitValue {
		return "(no value)"
	}
	return v
}

// String shows the change on one line.
func (c Change) String() string {
	switch {
	case !c.HadOld:
		return fmt.Sprintf("%s +%s %s", c.Kind, c.Name, show(c.New))
	case !c.HasNew:
		return fmt.Sprintf("%s -%s %s", c.Kind, c.Name, show(c.Old))
	}
	return fmt.Sprintf("%s ~%s %s -> %s", c.Kind, c.Name, show(c.Old), show(c.New))
}

// walkBarrier is a test seam called before each file of the snapshot walk is opened.
var walkBarrier func(rel string)

var (
	looseObject = regexp.MustCompile(`^(modules/.+/)?objects/[0-9a-f]{2}/[0-9a-f]{38,62}$`)
	packFile    = regexp.MustCompile(`^(modules/.+/)?objects/pack/pack-[0-9a-f]+\.(pack|idx|rev|bitmap|mtimes)$`)
	lfsObject   = regexp.MustCompile(`^lfs/objects/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{64}$`)
	objectDir   = regexp.MustCompile(`(^|/)objects/[0-9a-f]{2}(/[0-9a-f]{2})?$`)
)

// isPayload reports whether rel is object payload: a loose object or a pack file of the repository, of a submodule
// (modules/<name>/objects) or of LFS (lfs/objects). Everything else under objects/ (info/alternates, a .keep file,
// the commit graph) is hashed, and so is a submodule that happens to be named "objects".
func isPayload(rel string) bool {
	return looseObject.MatchString(rel) || packFile.MatchString(rel) || lfsObject.MatchString(rel)
}

// Snapshot reads the refs (git for-each-ref sees packed and loose), the local config and everything in the common
// git directory except object payloads (a lock file is recorded: a stale one zn left blocks the owner's git). Two reads of an unchanged repository are equal.
func (r *Repo) Snapshot() (Snapshot, error) {
	s := Snapshot{Refs: map[string]string{}, Config: map[string]string{}, Files: map[string]string{}}
	out, err := r.git("for-each-ref", "--format=%(refname)%00%(objectname)%00%(symref)")
	if err != nil {
		return s, err
	}
	for _, line := range strings.Split(out, "\n") {
		if line == "" {
			continue
		}
		f := strings.Split(line, "\x00")
		if len(f) != 3 {
			return s, fmt.Errorf("host: unreadable ref line %q", line)
		}
		// a symbolic ref (origin/HEAD) is recorded by its target: it moves only when retargeted, not with what it names
		s.Refs[f[0]] = f[1]
		if f[2] != "" {
			s.Refs[f[0]] = "-> " + f[2]
		}
	}
	out, err = r.git("config", "--local", "--list", "-z")
	if err != nil {
		return s, err
	}
	for _, ent := range strings.Split(out, "\x00") {
		if ent == "" {
			continue
		}
		key, val, hasVal := strings.Cut(ent, "\n")
		if !hasVal {
			val = implicitValue
		}
		if old, ok := s.Config[key]; ok {
			val = old + "\n" + val
		}
		s.Config[key] = val
	}
	err = r.walk(&s)
	return s, err
}

func vanished(err error) bool { return errors.Is(err, fs.ErrNotExist) }

// walk records the git directory's files; an entry that vanishes during the walk is skipped.
func (r *Repo) walk(s *Snapshot) error {
	return filepath.WalkDir(r.gitDir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			if vanished(err) {
				return nil
			}
			return err
		}
		rel, _ := filepath.Rel(r.gitDir, p)
		if rel == "." {
			return nil
		}
		rel = filepath.ToSlash(rel)
		if d.IsDir() {
			if objectDir.MatchString(rel) { // loose-object folders come and go with git's housekeeping
				return nil
			}
			ents, err := os.ReadDir(p)
			if err != nil {
				if vanished(err) {
					return nil
				}
				return err
			}
			if len(ents) == 0 {
				if info, err := d.Info(); err == nil {
					s.Files[rel+"/"] = fmt.Sprintf("dir %04o", info.Mode().Perm())
				}
			}
			return nil
		}
		if isPayload(rel) {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			if vanished(err) {
				return nil
			}
			return err
		}
		switch {
		case info.Mode()&fs.ModeSymlink != 0:
			target, err := os.Readlink(p)
			if err != nil {
				if vanished(err) {
					return nil
				}
				return err
			}
			s.Files[rel] = "link -> " + target
		case info.Mode().IsRegular():
			if walkBarrier != nil {
				walkBarrier(rel)
			}
			f, err := os.Open(p)
			if err != nil {
				if vanished(err) {
					return nil
				}
				return err
			}
			h := sha256.New()
			_, err = io.Copy(h, f)
			f.Close()
			if err != nil {
				if vanished(err) {
					return nil
				}
				return err
			}
			s.Files[rel] = fmt.Sprintf("%04o %x", info.Mode().Perm(), h.Sum(nil)[:8])
		}
		return nil
	})
}

// Diff lists what changed from a to b, sorted by kind and name.
func Diff(a, b Snapshot) []Change {
	var out []Change
	add := func(k Kind, x, y map[string]string) {
		for name, nv := range y {
			if ov, ok := x[name]; !ok || ov != nv {
				out = append(out, Change{Kind: k, Name: name, Old: ov, New: nv, HadOld: ok, HasNew: true})
			}
		}
		for name, ov := range x {
			if _, ok := y[name]; !ok {
				out = append(out, Change{Kind: k, Name: name, Old: ov, HadOld: true})
			}
		}
	}
	add(KindRef, a.Refs, b.Refs)
	add(KindConfig, a.Config, b.Config)
	add(KindFile, a.Files, b.Files)
	sort.Slice(out, func(i, j int) bool {
		if out[i].Kind != out[j].Kind {
			return out[i].Kind < out[j].Kind
		}
		return out[i].Name < out[j].Name
	})
	return out
}

// Delivery names one designed delivery (a raft's fetch-and-worktree) for Allowed.
type Delivery struct {
	Remote, Default string // the remote and its default branch that are fetched
	Branch          string // the new branch, e.g. zn/R0001-thing
	WorktreeName    string // the folder name git registers the new worktree under (.git/worktrees/<name>)
	// Extra admits further changes. Step 7 adds the fork push here: refs/remotes/<fork>/<branch> and, with push -u,
	// the branch's remote and merge config keys.
	Extra func(Change) bool
}

// Allowed returns the changes the delivery does not allow, which is none for the designed fetch-and-worktree: the
// new branch ref, the remote-tracking ref of the default branch (new or moved), FETCH_HEAD (per worktree when the
// fetch ran in one), those refs' files and reflogs, and the new worktree's own state. No config key.
func Allowed(changes []Change, d Delivery) []Change {
	var bad []Change
	for _, c := range changes {
		if !d.allows(c) {
			bad = append(bad, c)
		}
	}
	return bad
}

func (d Delivery) allows(c Change) bool {
	if d.Extra != nil && d.Extra(c) {
		return true
	}
	branchRef := "refs/heads/" + d.Branch
	trackRef := "refs/remotes/" + d.Remote + "/" + d.Default
	switch c.Kind {
	case KindRef:
		return (c.Name == branchRef && !c.HadOld && c.HasNew) || (c.Name == trackRef && c.HasNew)
	case KindFile:
		parts := strings.Split(c.Name, "/")
		if strings.HasSuffix(c.Name, "/") { // an empty folder that the allowed writes fill, or that they create empty
			if d.WorktreeName != "" && strings.HasPrefix(c.Name, "worktrees/"+d.WorktreeName+"/") {
				return true
			}
			for _, p := range []string{branchRef, trackRef, "logs/" + branchRef, "logs/" + trackRef, "worktrees/" + d.WorktreeName} {
				if strings.HasPrefix(p+"/", c.Name) {
					return true
				}
			}
			return false
		}
		return c.Name == "FETCH_HEAD" || c.Name == branchRef || c.Name == trackRef ||
			c.Name == "logs/"+branchRef || c.Name == "logs/"+trackRef ||
			(len(parts) == 3 && parts[0] == "worktrees" && parts[2] == "FETCH_HEAD") ||
			(d.WorktreeName != "" && strings.HasPrefix(c.Name, "worktrees/"+d.WorktreeName+"/"))
	}
	return false
}

// checkName refuses an empty name, a leading dash (an option to git) and, for refs, an invalid ref name.
func (r *Repo) checkName(what, name string, ref bool) error {
	if name == "" || strings.HasPrefix(name, "-") {
		return fmt.Errorf("host: %s %q is not usable", what, name)
	}
	if ref {
		if _, err := r.git("check-ref-format", "refs/heads/"+name); err != nil {
			return fmt.Errorf("host: %s %q is not a valid branch name", what, name)
		}
	}
	return nil
}

// FetchDefault fetches only the default branch of a configured remote into refs/remotes/<remote>/<branch>.
// Deviations from the Design's command, each for one reason: --refmap= (empty) so a configured fetch refspec cannot
// make git update other refs from the same fetch, and a forced refspec (+) so a force-pushed upstream branch does not
// leave the fetch stuck. It also takes no tags, no submodules, and prunes nothing. It writes that ref, FETCH_HEAD, the
// fetched objects and their reflog entries, and nothing else.
func (r *Repo) FetchDefault(remote, branch string) error {
	if err := r.checkName("remote", remote, false); err != nil {
		return err
	}
	if err := r.checkName("default branch", branch, true); err != nil {
		return err
	}
	out, err := r.git("remote")
	if err != nil {
		return err
	}
	configured := false
	for _, n := range strings.Split(out, "\n") {
		configured = configured || n == remote
	}
	if !configured {
		return fmt.Errorf("host: remote %q is not a configured remote of the host", remote)
	}
	_, err = r.write("fetch", "--no-tags", "--refmap=", "--upload-pack=git-upload-pack", "--recurse-submodules=no", remote,
		"+refs/heads/"+branch+":refs/remotes/"+remote+"/"+branch)
	return err
}

// checkWorktree validates a worktree request without running anything: the path stays inside the root and the names
// are usable. It returns the resolved path.
func (r *Repo) checkWorktree(path, branch, base string) (string, error) {
	abs, err := resolve(path)
	if err != nil {
		return "", err
	}
	if !within(r.root, abs) {
		return "", fmt.Errorf("host: worktree path %q is not inside the allowed root %q", path, r.root)
	}
	if err := r.checkName("branch", branch, true); err != nil {
		return "", err
	}
	if err := r.checkName("base", base, false); err != nil {
		return "", err
	}
	return abs, nil
}

// AddWorktree creates a worktree at path (inside the root) on the new branch, started from base and not tracking it.
func (r *Repo) AddWorktree(path, branch, base string) error {
	abs, err := r.checkWorktree(path, branch, base)
	if err != nil {
		return err
	}
	if err := r.checkLocalConfig(); err != nil {
		return err
	}
	if err := r.checkAttributes(base); err != nil {
		return err
	}
	if err := r.CheckBase(base); err != nil {
		return err
	}
	_, err = r.write("worktree", "add", "--no-track", "-b", branch, abs, base)
	return err
}

// FetchAndWorktree is the designed start of a raft: fetch the default branch of remote, then create the worktree at
// path on a new branch from refs/remotes/<remote>/<default>. The local default branch is not touched. Everything is
// checked before the fetch, so a refused request writes nothing.
func (r *Repo) FetchAndWorktree(remote, defaultBranch, branch, path string) error {
	base := "refs/remotes/" + remote + "/" + defaultBranch
	if _, err := r.checkWorktree(path, branch, base); err != nil {
		return err
	}
	if err := r.FetchDefault(remote, defaultBranch); err != nil {
		return err
	}
	return r.AddWorktree(path, branch, base)
}

// localConfigAllowed is the only local config a write runs with: what a normal clone or worktree setup holds. A key
// with a subsection is written "section.*.variable". Anything else is refused, because local keys can run programs
// (uploadpack, sshCommand, filter drivers, include of tracked files...). A setting to extend it is a later step.
var localConfigAllowed = map[string]bool{
	"core.repositoryformatversion": true, "core.filemode": true, "core.bare": true, "core.logallrefupdates": true,
	"core.ignorecase": true, "core.precomposeunicode": true, "core.symlinks": true, "core.autocrlf": true,
	"core.eol": true, "core.untrackedcache": true,
	"remote.*.url": true, "remote.*.fetch": true, "remote.*.pushurl": true, "remote.*.gh-resolved": true, "remote.*.tagopt": true,
	"branch.*.remote": true, "branch.*.merge": true, "branch.*.rebase": true, "branch.*.description": true,
	"user.name": true, "user.email": true, "pull.rebase": true, "pull.ff": true,
	"push.default": true, "push.autosetupremote": true, "init.defaultbranch": true,
	"submodule.*.url": true, "submodule.*.active": true,
	"extensions.worktreeconfig": true,
}

// configPattern turns a key as git lists it (section.subsection.variable) into its allowlist form.
func configPattern(key string) (pattern string, section string) {
	first, last := strings.Index(key, "."), strings.LastIndex(key, ".")
	if first < 0 {
		return key, key
	}
	if first == last {
		return key, key[:first]
	}
	return key[:first] + ".*" + key[last:], key[:first]
}

// checkLocalConfig refuses a write when the repository's own config (and its per-worktree config, when that extension
// is on) holds a key outside the allowlist, an include, or a remote URL that is not https, ssh, file or a local path.
func (r *Repo) checkLocalConfig() error {
	if r.skipConfigCheck {
		return nil
	}
	if err := r.checkConfigScope("--local"); err != nil {
		return err
	}
	// read as git reads a boolean: yes, on and 1 turn the worktree's own config on as true does
	if v, err := r.git("config", "--local", "--type=bool", "--get", "extensions.worktreeconfig"); err == nil && strings.TrimSpace(v) == "true" {
		return r.checkConfigScope("--worktree")
	}
	return nil
}

func (r *Repo) checkConfigScope(scope string) error {
	if scope == "--worktree" { // a worktree with no config.worktree of its own holds nothing to judge (git refuses to list it)
		p, err := r.git("rev-parse", "--path-format=absolute", "--git-path", "config.worktree")
		if err != nil {
			return err
		}
		if _, err := os.Lstat(strings.TrimSpace(p)); errors.Is(err, fs.ErrNotExist) {
			return nil
		}
	}
	out, err := r.git("config", scope, "--list", "--includes", "--show-origin", "-z")
	if err != nil {
		return err
	}
	parts := strings.Split(out, "\x00")
	// A remote's value may hold a credential, so no value is ever printed: the key and the file name it.
	refuse := func(origin, key, why string) error {
		file := strings.TrimPrefix(origin, "file:")
		if !filepath.IsAbs(file) {
			file = filepath.Join(r.dir, file)
		}
		return fmt.Errorf("host: refusing to run git: the config %s holds %q (its value is not shown), which %s. Remove it from that file, or move it to your global git config", file, key, why)
	}
	for i := 0; i+1 < len(parts); i += 2 {
		origin := parts[i]
		key, val, _ := strings.Cut(parts[i+1], "\n")
		pattern, section := configPattern(key)
		switch {
		case section == "include" || section == "includeif":
			return refuse(origin, key, "pulls in more config, which can come from tracked content")
		case !localConfigAllowed[pattern]:
			return refuse(origin, key, "is not a setting a normal clone holds and could run a program or change where git reads or writes")
		case pattern == "remote.*.tagopt" && val != "--no-tags": // zn clones a tracker with --no-tags (round 4)
			return refuse(origin, key, "fetches tags, and a tag can shadow the name origin/main")
		case pattern == "remote.*.url":
			if err := urlAllowed(val); err != nil {
				return refuse(origin, key, "is refused: "+err.Error())
			}
			// remote.*.pushurl is on the allowlist but its value is not judged here: a fetch and a worktree never use it, a
			// guard such as DISABLE is common, and Roles accepts it for a fork only when it is the fork's own fetch repository.
		}
	}
	return nil
}

var transportHelper = regexp.MustCompile(`^[A-Za-z0-9+.-]+::`)

// urlAllowed refuses a remote address that zn may not run git with. It is the safety reader of remote addresses
// (CheckAddress), not the identity grammar: a remote that is safe but has no owner/repository must not block a write.
// Both readers share one tokenizer and one refusal text, and the text never holds the address.
func urlAllowed(u string) error { return CheckAddress(u) }

// programAttributes are the attributes whose value names a driver from the git config, a program git runs on the
// content: filter= on checkout, merge= on a merge, diff= on a diff.
var programAttributes = []string{"filter=", "merge=", "diff="}

// filterDriver returns the driver a .gitattributes text selects with filter=, or "" (the first of programDriver).
func filterDriver(text string) string {
	_, drv := programDriver(text)
	return drv
}

// programDriver returns the first filter=, merge= or diff= setting a .gitattributes text holds, as the attribute
// (filter, merge or diff) and its driver, or "". Comment lines are skipped; a macro ([attr]) that sets one is found
// like any other line.
//
// Round 4 (review-003 F5): the setting is looked for anywhere in the text, comment lines included, wherever it is not
// part of a longer attribute name: git's blanks are only space, tab, CR and LF, so a line that starts with a form feed,
// a vertical tab, an NBSP or a NEL and then # is a pattern to git, and no comment rule of zn's is trusted to match git's.
func programDriver(text string) (attr, drv string) {
	// ASCII-only case folding keeps every byte where it is (strings.ToLower makes an invalid byte three, shrinks the
	// Kelvin sign and grows other letters, which moved the offsets off the original text: review-004 F2)
	b := []byte(text)
	for i, c := range b {
		if c >= 'A' && c <= 'Z' {
			b[i] = c + 'a' - 'A'
		}
	}
	lower := string(b)
	for _, a := range programAttributes {
		for from := 0; from < len(lower); {
			i := strings.Index(lower[from:], a)
			if i < 0 {
				break
			}
			at := from + i
			from = at + len(a)
			if at > 0 && strings.ContainsRune("abcdefghijklmnopqrstuvwxyz0123456789-_.", rune(lower[at-1])) {
				continue // part of a longer name (xfilter=)
			}
			end := from
			for end < len(text) && !strings.ContainsRune(" \t\r\n\f\v", rune(text[end])) {
				end++
			}
			if end > from {
				return a[:len(a)-1], text[from:end]
			}
		}
	}
	return "", ""
}

// checkAttributes refuses a worktree whose base commit (or the host's info/attributes) selects a filter, merge or diff
// driver: each runs a program of the user's config or the host's on the content. An attributes file is found in any
// case of its name (.GITATTRIBUTES is the attributes file on a case-insensitive disk). It is also how a host that
// adopts Git LFS is refused, at every worktree creation.
func (r *Repo) checkAttributes(base string) error {
	refuse := func(path, attr, drv string) error {
		return fmt.Errorf("host: refusing to create a worktree: %s selects the %s driver %q, which runs a program of the git config on the content (hosts that use Git LFS are refused for now)", quotePath(path), attr, drv)
	}
	out, err := r.git("ls-tree", "-r", "-z", "--name-only", base)
	if err != nil {
		return err
	}
	for _, p := range strings.Split(out, "\x00") {
		if !strings.EqualFold(path.Base(p), ".gitattributes") {
			continue
		}
		text, err := r.git("show", base+":"+p)
		if err != nil {
			return err
		}
		if attr, drv := programDriver(text); drv != "" {
			return refuse(p, attr, drv)
		}
	}
	if b, err := os.ReadFile(filepath.Join(r.gitDir, "info", "attributes")); err == nil {
		if attr, drv := programDriver(string(b)); drv != "" {
			return refuse("info/attributes", attr, drv)
		}
	}
	return nil
}

// quotePath is a repository path for a message: as it is when plain, else quoted for the shell with its control bytes
// escaped (a path may hold anything the repository's pusher chose).
func quotePath(p string) string { return shellQuote(p) }

// checkout runs a git command that checks content out (worktree add, checkout) with no user config at all: the reads
// environment pins the global and system config to nothing and the read pins stop hooks and fsmonitor, so no filter,
// attributes file, hook or other program of the user's runs on content someone else controls. The repository's own
// config is judged first, as for every write.
func (r *Repo) checkout(args ...string) (string, error) {
	if err := r.checkLocalConfig(); err != nil {
		return "", err
	}
	return r.exec(r.reads, append(append(append([]string{}, readPins...), "-c", "submodule.recurse=false"), args...))
}

// urlUserinfo matches the user information of a URL in a text.
var urlUserinfo = regexp.MustCompile(`([A-Za-z][A-Za-z0-9+.-]*://)[^/@\s'"]+@`)

// scrubURLs removes user information from every URL in a text (git's own messages and the arguments zn passes).
func scrubURLs(s string) string { return urlUserinfo.ReplaceAllString(s, "${1}") }
