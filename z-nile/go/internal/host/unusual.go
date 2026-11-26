package host

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// Reason names why a base directory is refused as a host.
type Reason string

// The reasons CheckHost refuses a directory, each its own.
const (
	ReasonNotRepo     Reason = "not-a-repository" // no git repository there
	ReasonBare        Reason = "bare-repository"  // a bare repository (with or without worktrees)
	ReasonSubmodule   Reason = "submodule"        // the directory is inside a submodule of another repository
	ReasonNotTop      Reason = "not-top-level"    // the directory is inside a repository but not its top level
	ReasonGitfile     Reason = "gitfile"          // .git is a file: a separate git dir or a linked worktree
	ReasonLocalConfig Reason = "local-config"
	ReasonTracked     Reason = "tracked-zn-folder" // the host already tracks a path under .tracker, .worktree or .cache
)

// UnusualHost is the refusal of a base directory as a host.
type UnusualHost struct {
	Reason Reason
	Detail string
}

func (e *UnusualHost) Error() string { return "host: " + string(e.Reason) + ": " + e.Detail }

func unusual(r Reason, format string, a ...any) error {
	return &UnusualHost{Reason: r, Detail: fmt.Sprintf(format, a...)}
}

// CheckHost refuses a directory that is not the top level of the main checkout of an ordinary clone, each case with
// its own reason: a bare repository, a submodule, a folder inside a repository, a gitfile (a separate git directory
// or a linked worktree), a local config the write allowlist would refuse (so init refuses before it writes anything)
// and a host that already tracks a path under .tracker, .worktree or .cache. It only reads, with the program-stopping
// pins on every call, the scrubbed read environment, and git's discovery stopped at the directory's parent, so a
// folder under a repository in the user's home is never taken for that repository.
func CheckHost(dir string) error {
	real, err := resolve(dir)
	if err != nil {
		return unusual(ReasonNotRepo, "%q cannot be read: %v", dir, err)
	}
	if st, err := os.Stat(real); err != nil || !st.IsDir() {
		return unusual(ReasonNotRepo, "%q is not a folder", dir)
	}
	r := &Repo{dir: real, reads: withoutRootPath(readEnv(os.Environ(), filepath.Dir(real)), real)}
	out, err := r.git("rev-parse", "--is-bare-repository")
	if err != nil {
		if top := enclosingRepository(real); top != "" {
			return unusual(ReasonNotTop, "%q is not the top level of its repository, which is %q: use that folder", dir, top)
		}
		return unusual(ReasonNotRepo, "%q is not a git repository (give the top level folder of the clone)", dir)
	}
	if strings.TrimSpace(out) == "true" {
		return unusual(ReasonBare, "%q is a bare repository: the base directory must be the main checkout of a normal clone", dir)
	}
	if out, err := r.git("rev-parse", "--show-superproject-working-tree"); err == nil && strings.TrimSpace(out) != "" {
		return unusual(ReasonSubmodule, "%q is inside a submodule of another repository: use the base directory of that repository", dir)
	}
	out, err = r.git("rev-parse", "--path-format=absolute", "--show-toplevel")
	if err != nil {
		return unusual(ReasonNotTop, "%q is not the top level of a repository (it is inside a git directory)", dir)
	}
	top, err := resolve(strings.TrimSpace(out))
	if err != nil || top != real {
		return unusual(ReasonNotTop, "%q is not the top level of its repository, which is %q: use that folder", dir, strings.TrimSpace(out))
	}
	if st, err := os.Lstat(filepath.Join(real, ".git")); err != nil || !st.IsDir() {
		return unusual(ReasonGitfile, "%q has a .git file, not a .git folder (a separate git directory or a linked worktree): the base directory must be the main checkout", dir)
	}
	if err := r.checkLocalConfig(); err != nil {
		return unusual(ReasonLocalConfig, "%s", strings.TrimPrefix(err.Error(), "host: refusing to run git: "))
	}
	spec := ":(literal)"
	if ic, err := r.git("config", "--bool", "--get", "core.ignorecase"); err == nil && strings.TrimSpace(ic) == "true" {
		spec = ":(icase,literal)" // a file system that ignores case: .Tracker collides with .tracker
	}
	out, err = r.git("ls-files", "-z", "--", spec+".tracker", spec+".worktree", spec+".cache")
	if err != nil {
		return err
	}
	if p, _, _ := strings.Cut(out, "\x00"); p != "" {
		return unusual(ReasonTracked, "the host already tracks %q: zn keeps .tracker, .worktree and .cache out of the host, so it cannot work here", p)
	}
	return nil
}

// walkStop is a test seam: the walk for an enclosing repository stops before this folder. Empty walks to the root.
var walkStop string

// enclosingRepository names the repository a folder sits inside, found by looking for .git in its parents with no git
// call. The user's home is skipped (a dotfiles repository there is not the project).
func enclosingRepository(dir string) string {
	home, _ := os.UserHomeDir()
	if home != "" {
		if h, err := resolve(home); err == nil {
			home = h
		}
	}
	for p := filepath.Dir(dir); p != filepath.Dir(p); p = filepath.Dir(p) {
		if walkStop != "" && p == walkStop {
			break
		}
		if _, err := os.Lstat(filepath.Join(p, ".git")); err == nil && p != home {
			return p
		}
	}
	return ""
}

// CheckBase refuses a commit (the upstream default branch a worktree will start from) that already tracks a path under
// .tracker, .worktree or .cache, whatever the case: the host would then carry zn's folders on every raft branch.
func (r *Repo) CheckBase(rev string) error {
	if err := r.checkName("base", rev, false); err != nil {
		return err
	}
	out, err := r.git("ls-tree", "-z", "--name-only", rev, "--")
	if err != nil {
		return err
	}
	for _, name := range strings.Split(out, "\x00") {
		for _, zn := range []string{".tracker", ".worktree", ".cache"} {
			if strings.EqualFold(name, zn) {
				return unusual(ReasonTracked, "the base %q tracks %q: zn keeps .tracker, .worktree and .cache out of the host, so no branch can start from it", rev, name)
			}
		}
	}
	return nil
}
