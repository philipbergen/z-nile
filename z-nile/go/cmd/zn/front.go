package main

import (
	"bytes"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"znile/internal/host"
)

// The front door's wiring for a host with a tracker (f0428 step 4): the resolver and the preparation are in
// internal/host; this file decides when they apply and what the engine is started with.

// wantsFrontDoor is false for the commands that read nothing of a tracker: no command, and the engine's help.
func wantsFrontDoor(args []string) bool {
	if len(args) == 0 {
		return false
	}
	switch args[0] {
	case "--help", "-h", "help":
		return false
	}
	return true
}

// allowedInAHost says whether a command is one of the few proven in a host repository (f0428 step 4). Everything else is
// refused there, by default: a command not named here runs nothing from a tracker, because nothing is let through that
// nobody read. The engine commands named here were read for what they execute (see the ticket): git, chmod, and bash on
// z-nile/lib/fence.sh through the linked engine, and nothing from the tracker's own files.
func allowedInAHost(args []string) bool {
	switch args[0] {
	case "list", "audit", "status", "guesses", "find":
		return true
	case "new":
		return len(args) > 1 && args[1] == "issue"
	}
	return false
}

// locate asks the one resolver where the tracker is, from the folder zn runs in. A nil tracker means none applies and
// the engine starts as it always did.
func locate(d deps) (*host.Tracker, error) {
	if d.cwd == nil {
		return nil, nil
	}
	cwd, err := d.cwd()
	if err != nil {
		return nil, nil
	}
	return host.Locate(cwd)
}

// projectsTimeout bounds the registry read (stub: the tests come first).
var projectsTimeout = time.Minute

// projectHomes are the project folders of the tracker's registry, asked of the engine's own reader (the registry has one
// reader, z-nile/engine/projects.luau, reached through z-nile/roots).
func projectHomes(payloadDir, work string, env []string) ([]string, error) {
	cmd := exec.Command(filepath.Join(payloadDir, "bin", "lune"), "run", filepath.Join("z-nile", "roots"), "--", "--projects")
	cmd.Dir, cmd.Env = work, env
	var out, errOut bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errOut
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("the tracker's %s cannot be read: %s", "z-nile/projects.toml", strings.TrimSpace(errOut.String()))
	}
	var homes []string
	for _, line := range strings.Split(strings.TrimSpace(out.String()), "\n") {
		if f := strings.Split(line, "\t"); len(f) == 3 {
			homes = append(homes, f[1])
		}
	}
	return homes, nil
}

// projectFor picks the project of the folder zn runs in: the project whose folder in the tracker worktree holds it,
// else the only project, else none (the engine then asks for --project, as at the root of any z-nile repository).
func projectFor(homes []string, cwd, work string) string {
	if real, err := filepath.EvalSymlinks(cwd); err == nil {
		cwd = real
	}
	if rel, err := filepath.Rel(work, cwd); err == nil && rel != "." && !strings.HasPrefix(rel, "..") {
		first, _, _ := strings.Cut(rel, string(filepath.Separator))
		for _, h := range homes {
			if h == first {
				return h
			}
		}
	}
	if len(homes) == 1 {
		return homes[0]
	}
	return ""
}

// engineEnv is the environment the engine gets in a host: an allowlist, never the caller's whole environment. Kept: the
// variables a program needs to run and find its user config (PATH, HOME, USER, LOGNAME, TMPDIR, LANG, LC_*, TERM, TZ,
// NO_COLOR, SSH_AUTH_SOCK and the XDG folders), git's identity and prompt switches (GIT_AUTHOR_*, GIT_COMMITTER_*,
// GIT_TERMINAL_PROMPT), and zn's own settings (ZN_*, PICKMAN_*). Dropped: every other GIT_* variable (a GIT_DIR or
// GIT_WORK_TREE from a hook would send the engine's commits and pushes to the host; GIT_CONFIG*, GIT_OBJECT_DIRECTORY
// and the like steer or run programs), loader variables (LD_*, DYLD_*) and everything else.
func engineEnv(env []string) []string {
	var out []string
	for _, kv := range env {
		k, _, _ := strings.Cut(kv, "=")
		keep := false
		switch k {
		case "PATH", "HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "TERM", "TZ", "NO_COLOR", "SSH_AUTH_SOCK",
			"XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "GIT_TERMINAL_PROMPT":
			keep = true
		default:
			keep = strings.HasPrefix(k, "LC_") || strings.HasPrefix(k, "ZN_") || strings.HasPrefix(k, "PICKMAN_") ||
				strings.HasPrefix(k, "GIT_AUTHOR_") || strings.HasPrefix(k, "GIT_COMMITTER_")
		}
		if keep {
			out = append(out, kv)
		}
	}
	return out
}

// withEnv sets the given variables, replacing any of the same name (a program reads the first of two).
func withEnv(env []string, set map[string]string) []string {
	out := make([]string, 0, len(env)+len(set))
	for _, e := range env {
		k, _, _ := strings.Cut(e, "=")
		if _, replaced := set[k]; !replaced {
			out = append(out, e)
		}
	}
	for k, v := range set {
		out = append(out, k+"="+v)
	}
	return out
}

// enterTracker prepares the tracker's worktree, then moves zn into it and says so in the environment the engine reads:
// ZN_TOP is the worktree, ZN_CWD the project's folder in it, ZN_LIVE=off keeps the engine from starting a live daemon
// binary found in the tracker, and ZN_ABSOLUTE_PATHS=1 makes it print absolute paths (the caller sits in the host).
func enterTracker(d deps, tr *host.Tracker, dir string, env []string) ([]string, error) {
	steps, err := tr.Prepare(dir)
	for _, s := range steps {
		fmt.Fprintln(d.stderr, "zn: "+s)
	}
	if err != nil {
		return nil, err
	}
	env = engineEnv(env)
	luneEnv := withLuneFirst(env, filepath.Join(dir, "bin"))
	homes, err := projectHomes(dir, tr.Work, luneEnv)
	if err != nil {
		return nil, err
	}
	cwd := tr.Host
	if d.cwd != nil {
		if c, err := d.cwd(); err == nil {
			cwd = c
		}
	}
	if d.chdir == nil {
		return nil, fmt.Errorf("zn cannot change folder")
	}
	if err := d.chdir(tr.Work); err != nil {
		return nil, err
	}
	return withEnv(env, map[string]string{
		"ZN_TOP": tr.Work, "ZN_CWD": projectFor(homes, cwd, tr.Work), "ZN_LIVE": "off", "ZN_ABSOLUTE_PATHS": "1",
	}), nil
}
