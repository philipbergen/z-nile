package main

import (
	"bytes"
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"

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

// projectHome is the one project's folder in the tracker's registry, asked of the engine's own reader (the registry
// has one reader, z-nile/engine/projects.luau, reached through z-nile/roots). A tracker that holds several projects
// has no default: the engine then asks for --project, as it does at the root of any z-nile repository.
func projectHome(lune, work string, env []string) (string, error) {
	cmd := exec.Command(lune, "run", filepath.Join("z-nile", "roots"), "--", "--projects")
	cmd.Dir, cmd.Env = work, env
	var out, errOut bytes.Buffer
	cmd.Stdout, cmd.Stderr = &out, &errOut
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("the tracker's %s cannot be read: %s", "z-nile/projects.toml", strings.TrimSpace(errOut.String()))
	}
	var homes []string
	for _, line := range strings.Split(strings.TrimSpace(out.String()), "\n") {
		if f := strings.Split(line, "\t"); len(f) == 3 {
			homes = append(homes, f[1])
		}
	}
	if len(homes) == 1 {
		return homes[0], nil
	}
	return "", nil
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
// ZN_TOP is the worktree and ZN_CWD the project's folder in it, which is how the engine picks the project.
func enterTracker(d deps, tr *host.Tracker, dir string, env []string) ([]string, error) {
	steps, err := tr.Prepare(dir)
	for _, s := range steps {
		fmt.Fprintln(d.stderr, "zn: "+s)
	}
	if err != nil {
		return nil, err
	}
	luneEnv := withLuneFirst(env, filepath.Join(dir, "bin"))
	home, err := projectHome(filepath.Join(dir, "bin", "lune"), tr.Work, luneEnv)
	if err != nil {
		return nil, err
	}
	if d.chdir == nil {
		return nil, fmt.Errorf("zn cannot change folder")
	}
	if err := d.chdir(tr.Work); err != nil {
		return nil, err
	}
	set := map[string]string{"ZN_TOP": tr.Work, "ZN_CWD": home}
	return withEnv(env, set), nil
}
