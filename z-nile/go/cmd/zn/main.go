// Command zn is z-nile's one program: it carries this platform's Lune and the Luau engine, extracts them once to a
// per-user cache folder and runs the engine's commands with them, so a machine needs no Lune. `zn version` runs in Go.
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"time"

	"znile/internal/host"
	"znile/internal/payload"
)

// build is stamped by the build with -ldflags -X main.build=<id>.
var build = "dev"

// Exit codes: 0 is the engine's own (it replaces this process), the others are zn's.
const (
	exitRefused     = 4 // zn's own refusal: the engine uses 1 constantly and 3 means "no payload"
	exitUnavailable = 3
)

// deps are the things run touches outside itself, so a test can stand in for each.
type deps struct {
	embedded func() (payload.Payload, bool)
	exec     func(path string, argv, env []string) error
	env      []string
	stdout   io.Writer
	stderr   io.Writer
	cwd      func() (string, error) // the folder zn init is run in
	chdir    func(string) error     // changes zn's own folder before the engine starts (a host's tracker worktree)
	lookup   host.Lookup            // what GitHub says about the host's remotes (zn init)
}

func main() {
	os.Exit(run(os.Args[1:], deps{
		embedded: payload.Embedded,
		exec:     syscall.Exec,
		env:      os.Environ(),
		stdout:   os.Stdout,
		stderr:   os.Stderr,
		cwd:      osCwd,
		chdir:    os.Chdir,
		lookup:   ghLookup(runGH),
	}))
}

// run is zn: `version` is answered here, every other command goes to the engine under the extracted Lune. It returns
// only when something failed or the (fake) exec returned; a real exec replaces the process.
func run(args []string, d deps) int {
	if len(args) > 0 && args[0] == "init" { // answered in Go: the engine is not needed and not started
		return runInit(args[1:], d)
	}
	p, ok := d.embedded()
	var tracker *host.Tracker
	if ok && wantsFrontDoor(args) && !(len(args) == 1 && args[0] == "version") {
		var err error
		if tracker, err = locate(d); err != nil { // refused before the engine, the cache or any git write
			fmt.Fprintf(d.stderr, "zn: %v\n", err)
			return exitRefused
		}
		if tracker != nil && !allowedInAHost(args) {
			what := args[0]
			if what == "new" && len(args) > 1 {
				what += " " + args[1]
			}
			fmt.Fprintf(d.stderr, "zn: %s: not yet available in a host repository\n", what)
			return exitRefused
		}
	}
	if len(args) == 1 && args[0] == "version" {
		if !ok {
			fmt.Fprintf(d.stdout, "zn %s %s/%s payload none\n", build, runtime.GOOS, runtime.GOARCH)
			return 0
		}
		id := p.ID
		if p.Dirty {
			id += "-dirty"
		}
		fmt.Fprintf(d.stdout, "zn %s %s/%s payload %s lune %s (%s pin)\n", build, runtime.GOOS, runtime.GOARCH, id, p.LuneSum(), p.Kind)
		return 0
	}
	if !ok {
		fmt.Fprintln(d.stderr, "zn: this binary has no embedded Lune and engine (it was built with a plain go build). Build it with z-nile/lib/znbuild.sh.")
		return exitUnavailable
	}
	cache, err := payload.CacheFolder(d.env)
	if err != nil {
		fmt.Fprintf(d.stderr, "zn: %v\n", err)
		return exitRefused
	}
	dir, _, err := payload.ExtractNotify(cache, p, d.stderr)
	if err != nil {
		fmt.Fprintf(d.stderr, "zn: %v\n", err)
		return exitRefused
	}
	lune := filepath.Join(dir, "bin", "lune")
	env := d.env
	if tracker != nil {
		lock, err := host.LockTracker(tracker.Dir, 30*time.Second)
		if err != nil {
			fmt.Fprintf(d.stderr, "zn: %v\n", err)
			return exitRefused
		}
		defer lock.Release() // a real exec never returns: the lock then lives on in the engine
		lock.KeepAcrossExec()
		if env, err = enterTracker(d, tracker, dir, d.env); err != nil {
			fmt.Fprintf(d.stderr, "zn: %v\n", err)
			return exitRefused
		}
	}
	argv := append([]string{lune, "run", filepath.Join(dir, "z-nile", "engine", "main"), "--"}, args...)
	if err := d.exec(lune, argv, withLuneFirst(env, filepath.Join(dir, "bin"))); err != nil {
		fmt.Fprintf(d.stderr, "zn: cannot run %s from the cache folder %s: %v (a noexec mount does this: set ZN_CACHE to a folder that allows running programs)\n", lune, dir, err)
		return exitRefused
	}
	return 0
}

// withLuneFirst puts the extracted Lune's folder first on PATH, so the engine's own `lune` spawns find it. An unset or
// empty PATH becomes the system default, and an empty entry (which would mean the current folder) is dropped.
func withLuneFirst(env []string, bin string) []string {
	out := make([]string, 0, len(env)+1)
	var entries []string
	for _, e := range env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			for _, part := range strings.Split(v, ":") {
				if part != "" {
					entries = append(entries, part)
				}
			}
			continue
		}
		out = append(out, e)
	}
	if len(entries) == 0 {
		entries = []string{"/usr/bin", "/bin"}
	}
	return append(out, "PATH="+bin+":"+strings.Join(entries, ":"))
}
