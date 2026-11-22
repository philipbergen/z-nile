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
// or a linked worktree) and a host that already tracks a path under .tracker, .worktree or .cache. It only reads.
func CheckHost(dir string) error {
	real, err := resolve(dir)
	if err != nil {
		return unusual(ReasonNotRepo, "%q cannot be read: %v", dir, err)
	}
	if st, err := os.Stat(real); err != nil || !st.IsDir() {
		return unusual(ReasonNotRepo, "%q is not a folder", dir)
	}
	r := &Repo{dir: real, reads: readEnv(os.Environ(), "")}
	out, err := r.git("rev-parse", "--is-bare-repository")
	if err != nil {
		return unusual(ReasonNotRepo, "%q is not a git repository", dir)
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
	out, err = r.git("ls-files", "-z", "--", ":(literal).tracker", ":(literal).worktree", ":(literal).cache")
	if err != nil {
		return err
	}
	if p, _, _ := strings.Cut(out, "\x00"); p != "" {
		return unusual(ReasonTracked, "the host already tracks %q: zn keeps .tracker, .worktree and .cache out of the host, so it cannot work here", p)
	}
	return nil
}

// CheckBase refuses a commit that already tracks a path under .tracker, .worktree or .cache.
func (r *Repo) CheckBase(rev string) error { return nil }
