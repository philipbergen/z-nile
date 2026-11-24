package main

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"path/filepath"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"znile/internal/host"
	"znile/internal/lunepin"
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
	case "list", "audit", "guesses", "find":
		return true
	case "status": // reading a status and moving one to preparing; prepared edits tracked files in the worktree
		for _, a := range args[1:] { // anywhere: an option that takes a value would shift a positional count (review-004 F4)
			if a == "prepared" {
				return false
			}
		}
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

// projectsTimeout bounds the registry read (a test lowers it).
var projectsTimeout = time.Minute

// projectHomes are the project folders of the tracker's registry, asked of the engine's own reader (the registry has one
// reader, z-nile/engine/projects.luau, reached through z-nile/roots) in the payload, named by its absolute path, so no
// file of the tracker's is ever run for it. The read is bounded and stopped with everything it started.
func projectHomes(ctx context.Context, payloadDir, work string, env []string) ([]string, error) {
	ctx, cancel := context.WithTimeout(ctx, projectsTimeout)
	defer cancel()
	var out, errOut bytes.Buffer
	// with a lifeline: the read dies with zn, even when zn is killed outright
	if err := lunepin.RunLifeline(ctx, work, env, &out, &errOut, filepath.Join(payloadDir, "bin", "lune"), "run", filepath.Join(payloadDir, "z-nile", "roots"), "--", "--projects"); err != nil {
		if ctx.Err() != nil {
			return nil, fmt.Errorf("reading the tracker's registry %s took longer than %s. Run the command again; if it stops again, remove the folder %s and zn extracts its engine anew", filepath.Join(work, "z-nile", "projects.toml"), projectsTimeout, payloadDir)
		}
		return nil, fmt.Errorf("the tracker's registry %s cannot be read: %s. Fix it in the tracker's main (commit and push), then run the command again", filepath.Join(work, "z-nile", "projects.toml"), host.TerminalSafe(strings.TrimSpace(errOut.String())))
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

// engineEnvKept are the variables the engine gets in a host, by name: an allowlist, never the caller's whole
// environment. What a program needs to run and find its user config (PATH, HOME, USER, LOGNAME, TMPDIR, LANG, LC_*,
// TERM, TZ, NO_COLOR, SSH_AUTH_SOCK and the XDG folders), git's identity and prompt switches (GIT_AUTHOR_*,
// GIT_COMMITTER_*, GIT_TERMINAL_PROMPT), and the two of zn's own settings that only narrow what the engine does: ZN_BOUNDED_DEADLINE (the reaper's mark of a bounded run) and ZN_ENGINE_CPU (a CPU limit).
// PICKMAN_PUBLISH is dropped (round 4): publishing turned off leaves untracked files that wedge the worktree. Dropped: every other GIT_* variable (a GIT_DIR or GIT_WORK_TREE from a hook would send the engine's
// commits and pushes to the host; GIT_CONFIG*, GIT_OBJECT_DIRECTORY and the like steer git or run programs), every other
// ZN_* and PICKMAN_* (ZN_REAL_GIT, PICKMAN_FENCE_REAL_GIT and ZN_REAL_GH name the git and gh the engine runs,
// ZN_PUBLISH_BROKER where it publishes, PICKMAN_FENCE_HOOKS the hooks git runs, ZN_ROOT, ZN_DISPATCH* and ZN_LIVE_* other
// checkouts and programs, ZN_MEASURE_* files it writes), loader variables (LD_*, DYLD_*) and everything else.
var engineEnvKept = map[string]bool{
	"PATH": true, "HOME": true, "USER": true, "LOGNAME": true, "TMPDIR": true, "LANG": true, "TERM": true, "TZ": true,
	"NO_COLOR": true, "SSH_AUTH_SOCK": true, "XDG_CONFIG_HOME": true, "XDG_CACHE_HOME": true, "XDG_DATA_HOME": true,
	"GIT_TERMINAL_PROMPT": true, "ZN_BOUNDED_DEADLINE": true, "ZN_ENGINE_CPU": true,
}

// engineEnv is the environment the engine gets in a host (engineEnvKept).
func engineEnv(env []string) []string {
	var out []string
	for _, kv := range env {
		k, _, _ := strings.Cut(kv, "=")
		if engineEnvKept[k] || strings.HasPrefix(k, "LC_") || strings.HasPrefix(k, "GIT_AUTHOR_") || strings.HasPrefix(k, "GIT_COMMITTER_") {
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

// gitPins are the settings every git the engine runs in a tracker gets, as GIT_CONFIG_COUNT/KEY/VALUE (which win over
// every config file): no hook (hooksDir is an empty folder zn keeps), no fsmonitor, no background gc or maintenance
// (a daemon that would outlive the command), no ext:: or fd:: transport, no submodule recursion. The owner's global and
// system config apply otherwise.
func gitPins(hooksDir string) map[string]string {
	pins := [][2]string{{"core.hooksPath", hooksDir}, {"core.fsmonitor", "false"}, {"gc.auto", "0"}, {"maintenance.auto", "false"},
		{"protocol.ext.allow", "never"}, {"protocol.fd.allow", "never"}, {"submodule.recurse", "false"}}
	set := map[string]string{"GIT_CONFIG_COUNT": strconv.Itoa(len(pins))}
	for i, p := range pins {
		set["GIT_CONFIG_KEY_"+strconv.Itoa(i)], set["GIT_CONFIG_VALUE_"+strconv.Itoa(i)] = p[0], p[1]
	}
	return set
}

// enterTracker prepares the tracker's worktree, then moves zn into it and says so in the environment the engine reads:
// ZN_TOP is the worktree, ZN_CWD the project's folder in it, ZN_LIVE=off keeps the engine from starting a live daemon
// binary found in the tracker, ZN_ABSOLUTE_PATHS=1 makes it print absolute paths (the caller sits in the host), and
// ZN_FRONT_DOOR=1 tells it a front door judges every commit it checks out (it merges nothing it published); the git
// pins (gitPins) come last.
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
	homes, err := projectHomes(context.Background(), dir, tr.Work, luneEnv)
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
		return nil, fmt.Errorf("zn cannot change to the folder %s", tr.Work)
	}
	if err := d.chdir(tr.Work); err != nil {
		return nil, err
	}
	set := gitPins(tr.HooksDir())
	for k, v := range map[string]string{"ZN_TOP": tr.Work, "ZN_CWD": projectFor(homes, cwd, tr.Work), "ZN_LIVE": "off",
		"ZN_ABSOLUTE_PATHS": "1", "ZN_FRONT_DOOR": "1"} {
		set[k] = v
	}
	return withEnv(env, set), nil
}

// terminalFilter passes what the engine prints to the terminal with every control byte escaped except a newline and a
// tab (host.TerminalSafe's escapes), so text the tracker supplied cannot drive the terminal. A UTF-8 sequence split
// across writes is held until it is whole; Flush writes what is held at the end.
type terminalFilter struct {
	w    io.Writer
	held []byte
}

func newTerminalFilter(w io.Writer) *terminalFilter { return &terminalFilter{w: w} }

func (f *terminalFilter) Write(p []byte) (int, error) {
	data := append(f.held, p...)
	cut := len(data)
	for i := len(data) - 1; i >= 0 && i >= len(data)-3; i-- { // an incomplete sequence at the end waits for its rest
		if utf8.RuneStart(data[i]) {
			if !utf8.FullRune(data[i:]) {
				cut = i
			}
			break
		}
	}
	f.held = append([]byte{}, data[cut:]...)
	if _, err := io.WriteString(f.w, escapeLines(string(data[:cut]))); err != nil {
		return 0, err
	}
	return len(p), nil
}

// Flush writes a held incomplete sequence, escaped.
func (f *terminalFilter) Flush() {
	if len(f.held) > 0 {
		io.WriteString(f.w, host.TerminalSafe(string(f.held)))
		f.held = nil
	}
}

// escapeLines escapes a text line by line, keeping its newlines and tabs.
func escapeLines(s string) string {
	parts := strings.Split(s, "\n")
	for i, p := range parts {
		cells := strings.Split(p, "\t")
		for j, c := range cells {
			cells[j] = host.TerminalSafe(c)
		}
		parts[i] = strings.Join(cells, "\t")
	}
	return strings.Join(parts, "\n")
}
