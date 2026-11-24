// Command zn is z-nile's one program: it carries this platform's Lune and the Luau engine, extracts them once to a
// per-user cache folder and runs the engine's commands with them, so a machine needs no Lune. `zn version` runs in Go.
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
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
	cwd      func() (string, error)                                                       // the folder zn init is run in
	chdir    func(string) error                                                           // changes zn's own folder before the engine starts (a host's tracker worktree)
	lookup   host.Lookup                                                                  // what GitHub says about the host's remotes (zn init)
	child    func(path string, argv, env []string, stdout, stderr io.Writer) (int, error) // runs the engine as zn's child (a host): its exit code
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
		child:    runChild,
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
			fmt.Fprintf(d.stderr, "zn: %s: not yet available in a host repository. Here zn runs new issue, list, audit, status, guesses and find (and help, version and init): use one of those, or run %s in a z-nile repository of its own\n", what, what)
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
	argv := append([]string{lune, "run", filepath.Join(dir, "z-nile", "engine", "main"), "--"}, args...)
	if tracker != nil {
		return runInTracker(d, tracker, dir, lune, argv)
	}
	if err := d.exec(lune, argv, withLuneFirst(d.env, filepath.Join(dir, "bin"))); err != nil {
		fmt.Fprintf(d.stderr, "zn: cannot run %s from the cache folder %s: %v (a noexec mount does this: set ZN_CACHE to a folder that allows running programs)\n", lune, dir, err)
		return exitRefused
	}
	return 0
}

// runInTracker runs the engine in a host's tracker: zn takes the tracker's lock, prepares the worktree, then runs the
// engine as its child (not by exec), holding the lock itself until the engine has ended, so no program the engine
// starts ever holds it. What the engine prints passes through a filter that escapes control bytes, so text the tracker
// supplied (a title, a path) cannot drive the terminal. After the engine, Refresh judges the main it published to and
// only then moves the standing worktree there: the engine itself never checks out a commit zn did not judge.
func runInTracker(d deps, tracker *host.Tracker, dir, lune string, argv []string) int {
	lock, err := host.LockTracker(tracker.Dir, 30*time.Second)
	if err != nil {
		fmt.Fprintf(d.stderr, "zn: %v\n", err)
		return exitRefused
	}
	defer lock.Release()
	env, err := enterTracker(d, tracker, dir, d.env)
	if err != nil {
		fmt.Fprintf(d.stderr, "zn: %v\n", err)
		return exitRefused
	}
	child := d.child
	if child == nil {
		child = func(path string, argv, env []string, _, _ io.Writer) (int, error) { return 0, d.exec(path, argv, env) }
	}
	out, errOut := newTerminalFilter(d.stdout), newTerminalFilter(d.stderr)
	code, err := child(lune, argv, withLuneFirst(env, filepath.Join(dir, "bin")), out, errOut)
	out.Flush()
	errOut.Flush()
	if err != nil {
		fmt.Fprintf(d.stderr, "zn: cannot run %s from the cache folder %s: %v (a noexec mount does this: set ZN_CACHE to a folder that allows running programs)\n", lune, dir, err)
		return exitRefused
	}
	steps, err := tracker.Refresh(dir)
	for _, s := range steps {
		fmt.Fprintln(d.stderr, "zn: "+s)
	}
	if err != nil {
		fmt.Fprintf(d.stderr, "zn: the command ran, but the tracker's worktree stays where it was: %v\n", err)
	}
	return code
}

// runChild runs the engine as zn's child with zn's terminal on its standard input, forwards the signals a terminal or
// a supervisor sends (so the engine, not zn, decides how to stop), and returns the engine's exit code (128+n for a
// signal n, as a shell reports it).
func runChild(path string, argv, env []string, stdout, stderr io.Writer) (int, error) {
	cmd := exec.Command(path, argv[1:]...)
	cmd.Env, cmd.Stdin, cmd.Stdout, cmd.Stderr = env, os.Stdin, stdout, stderr
	sigs := make(chan os.Signal, 4)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP, syscall.SIGQUIT)
	defer signal.Stop(sigs)
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	done := make(chan struct{})
	go func() { // ends when the engine ends (done is closed after Wait)
		for {
			select {
			case s := <-sigs:
				if s == syscall.SIGTERM || s == syscall.SIGHUP { // a terminal's ^C and ^\ reach the engine by themselves
					cmd.Process.Signal(s)
				}
			case <-done:
				return
			}
		}
	}()
	err := cmd.Wait()
	close(done)
	var ee *exec.ExitError
	switch {
	case err == nil:
		return 0, nil
	case errors.As(err, &ee):
		if ws, ok := ee.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
			return 128 + int(ws.Signal()), nil
		}
		return ee.ExitCode(), nil
	}
	return 0, err
}

// withLuneFirst puts the extracted Lune's folder first on PATH, so the engine's own `lune` spawns find it. An unset or
// empty PATH becomes the system default, and every entry that is not an absolute path (an empty one, which means the
// current folder, or ./bin) is dropped: zn changes folder before the engine starts, into a tracker someone else writes.
func withLuneFirst(env []string, bin string) []string {
	out := make([]string, 0, len(env)+1)
	var entries []string
	for _, e := range env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			for _, part := range strings.Split(v, ":") {
				if filepath.IsAbs(part) {
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
