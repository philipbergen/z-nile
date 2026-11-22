// Package host does the git work zn does inside a host repository it does not own (f0428 step 1): a snapshot of the
// host's refs, config and .git files that can be compared, and the one designed fetch-and-worktree write.
// Every git call names its repository with -C, runs with a scrubbed environment and is confined to a root the
// caller passed, so a path outside it is refused before git runs.
package host

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// gitTimeout bounds every git call.
const gitTimeout = 2 * time.Minute

// Repo is a host repository (its main checkout or one of its worktrees) with the root every path must stay under.
type Repo struct {
	dir     string // resolved checkout folder
	root    string // resolved allowed root
	gitDir  string // resolved common git directory
	envList []string
}

// Open returns the repository at dir, refusing a dir that is not inside root (symlinks and .. resolved first).
func Open(root, dir, hooksDir string) (*Repo, error) {
	_ = hooksDir
	r := &Repo{envList: readEnv(os.Environ(), "")}
	var err error
	if r.root, err = resolve(root); err != nil {
		return nil, fmt.Errorf("host: allowed root %q: %w", root, err)
	}
	if r.dir, err = resolve(dir); err != nil {
		return nil, fmt.Errorf("host: %q: %w", dir, err)
	}
	if !within(r.root, r.dir) {
		return nil, fmt.Errorf("host: %q is not inside the allowed root %q", dir, root)
	}
	out, err := r.git("rev-parse", "--path-format=absolute", "--git-common-dir")
	if err != nil {
		return nil, err
	}
	if r.gitDir, err = resolve(strings.TrimSpace(out)); err != nil {
		return nil, err
	}
	return r, nil
}

// Dir is the checkout folder the repository was opened at.
func (r *Repo) Dir() string { return r.dir }

// scrubbedEnv drops every inherited GIT_* variable and points the global and system config at nothing, so the
// user's own git config neither leaks in nor is written.
func readEnv(in []string, ceiling string) []string {
	var out []string
	for _, kv := range in {
		if !strings.HasPrefix(kv, "GIT_") {
			out = append(out, kv)
		}
	}
	return append(out,
		"GIT_CONFIG_GLOBAL=/dev/null",
		"GIT_CONFIG_SYSTEM=/dev/null",
		"GIT_CONFIG_NOSYSTEM=1",
		"GIT_TERMINAL_PROMPT=0",
		"GIT_OPTIONAL_LOCKS=0",
	)
}

// git runs one git command in the repository and returns its stdout.
func (r *Repo) git(args ...string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), gitTimeout)
	defer cancel()
	full := append([]string{"-C", r.dir, "-c", "gc.auto=0", "-c", "maintenance.auto=false"}, args...)
	cmd := exec.CommandContext(ctx, "git", full...)
	cmd.Env = r.envList
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("host: git %s: %w: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
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

// within reports whether p is root or below it.
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
	KindFile   Kind = "file"   // a file of the common git directory, objects/ aside
)

// Snapshot is the host's refs, local config and git-directory files at one moment.
type Snapshot struct {
	Refs   map[string]string // ref name -> object id (or "-> target" for a symbolic ref), loose and packed alike
	Config map[string]string // config key -> its values joined by newlines
	Files  map[string]string // path relative to the git directory -> content hash
}

// Change is one difference between two snapshots; an empty Old is an addition, an empty New a removal.
type Change struct {
	Kind Kind
	Name string
	Old  string
	New  string
	// HadOld and HasNew say whether the item existed before and after.
	HadOld, HasNew bool
}

// String shows the change on one line.
func (c Change) String() string {
	switch {
	case c.Old == "":
		return fmt.Sprintf("%s +%s %s", c.Kind, c.Name, c.New)
	case c.New == "":
		return fmt.Sprintf("%s -%s %s", c.Kind, c.Name, c.Old)
	}
	return fmt.Sprintf("%s ~%s %s -> %s", c.Kind, c.Name, c.Old, c.New)
}

// Snapshot reads the refs (git for-each-ref sees packed and loose), the local config and every git-directory file
// except under objects/. Two reads of an unchanged repository are equal.
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
		key, val, _ := strings.Cut(ent, "\n")
		if old, ok := s.Config[key]; ok {
			val = old + "\n" + val
		}
		s.Config[key] = val
	}
	err = filepath.WalkDir(r.gitDir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, _ := filepath.Rel(r.gitDir, p)
		if d.IsDir() {
			if rel == "objects" {
				return filepath.SkipDir
			}
			return nil
		}
		if !d.Type().IsRegular() {
			return nil
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		sum := sha256.Sum256(b)
		s.Files[filepath.ToSlash(rel)] = fmt.Sprintf("%x", sum[:8])
		return nil
	})
	return s, err
}

// Diff lists what changed from a to b, sorted by kind and name.
func Diff(a, b Snapshot) []Change {
	var out []Change
	add := func(k Kind, x, y map[string]string) {
		for name, nv := range y {
			if ov, ok := x[name]; !ok || ov != nv {
				out = append(out, Change{Kind: k, Name: name, Old: x[name], New: nv})
			}
		}
		for name, ov := range x {
			if _, ok := y[name]; !ok {
				out = append(out, Change{Kind: k, Name: name, Old: ov})
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

// FetchDefault fetches only the default branch of remote, no tags and no submodules, into refs/remotes/<remote>/<branch>.
// It writes that ref, FETCH_HEAD, the fetched objects and their reflog entries, and nothing else.
func (r *Repo) FetchDefault(remote, branch string) error {
	if err := r.checkName("remote", remote, false); err != nil {
		return err
	}
	if err := r.checkName("default branch", branch, true); err != nil {
		return err
	}
	_, err := r.git("fetch", "--no-tags", "--recurse-submodules=no", remote,
		"refs/heads/"+branch+":refs/remotes/"+remote+"/"+branch)
	return err
}

// AddWorktree creates a worktree at path (inside the root) on the new branch, started from base and not tracking it.
func (r *Repo) AddWorktree(path, branch, base string) error {
	abs, err := resolve(path)
	if err != nil {
		return err
	}
	if !within(r.root, abs) {
		return fmt.Errorf("host: worktree path %q is not inside the allowed root %q", path, r.root)
	}
	if err := r.checkName("branch", branch, true); err != nil {
		return err
	}
	if err := r.checkName("base", base, false); err != nil {
		return err
	}
	_, err = r.git("worktree", "add", "--no-track", "-b", branch, abs, base)
	return err
}

// FetchAndWorktree is the designed start of a raft: fetch the default branch of remote, then create the worktree at
// path on a new branch from refs/remotes/<remote>/<default>. The local default branch is not touched.
func (r *Repo) FetchAndWorktree(remote, defaultBranch, branch, path string) error {
	if err := r.FetchDefault(remote, defaultBranch); err != nil {
		return err
	}
	return r.AddWorktree(path, branch, "refs/remotes/"+remote+"/"+defaultBranch)
}

// Delivery names one designed delivery for Allowed. Extra is where later steps add entries (step 7: the fork push).
type Delivery struct {
	Remote, Default, Branch, WorktreeName string
	Extra                                 func(Change) bool
}

// Allowed returns the changes the delivery does not allow.
func Allowed(changes []Change, d Delivery) []Change { return nil }

// walkBarrier is a test seam called before each file of the snapshot walk is opened.
var walkBarrier func(rel string)

// readGit runs a read-only git command.
func (r *Repo) readGit(args ...string) (string, error) { return r.git(args...) }

// writeEnv builds the environment of the commands that write.
func writeEnv(in []string, ceiling string) []string { return readEnv(in, ceiling) }
