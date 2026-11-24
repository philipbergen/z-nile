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
			switch {
			case what == "new" && len(args) > 1:
				what += " " + args[1]
			case what == "status": // P8(b): it edits the ticket in zn's worktree, which no tracker merge carries yet
				what = "status <id> prepared (it edits tracked files in zn's worktree, and the tracker merge that would carry them is not built yet)"
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
	if d.child == nil { // an exec would drop the lock, the filter and the refresh
		fmt.Fprintln(d.stderr, "zn: this zn cannot run the engine as its own child, which a host repository needs. Build zn with z-nile/lib/znbuild.sh, then run the command again")
		return exitRefused
	}
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
	out, errOut := newTerminalFilter(d.stdout), newTerminalFilter(d.stderr)
	code, err := d.child(lune, argv, withLuneFirst(env, filepath.Join(dir, "bin"), tracker.Host), out, errOut)
	out.Flush()
	errOut.Flush()
	switch {
	case errors.Is(err, errNotStarted):
		fmt.Fprintf(d.stderr, "zn: cannot run %s from the cache folder %s: %v (a noexec mount does this: set ZN_CACHE to a folder that allows running programs)\n", lune, dir, err)
		return exitRefused
	case err != nil: // it ran: what it published is refreshed all the same
		fmt.Fprintf(d.stderr, "zn: the engine ended with an error: %s\n", host.TerminalSafe(err.Error()))
		if code == 0 {
			code = 1
		}
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

// childStdin is the engine's standard input: zn's own (a test gives another).
var childStdin io.Reader = os.Stdin

// errNotStarted marks a child that never ran (a noexec mount, a missing shell), unlike one that ran and failed.
var errNotStarted = errors.New("the engine could not be started")

// engineLifeline runs "$@" (the engine) in the shell's foreground, beside a watcher of fd 3 in the background: a pipe
// whose only write end zn holds. When zn ends, however it ends (SIGKILL, or SIGPIPE on its output), the pipe closes and
// the watcher kills the whole process group, the engine's git children included. The engine keeps zn's standard input
// and default signal dispositions (a background command of a non-interactive shell would ignore INT and QUIT).
const engineLifeline = `{ read -r _ <&3; kill -KILL 0; } </dev/null >/dev/null 2>&1 &
w=$!
exec 3<&-
"$@"
s=$?
kill "$w" 2>/dev/null
exit "$s"`

// forwarded are the signals zn passes to the engine's process group: the engine has a group of its own (so the
// lifeline can end it whole), which a terminal's Ctrl-C, Ctrl-\ and Ctrl-Z no longer reach by themselves. A signal
// ignored when zn started (nohup's HUP) is left ignored, and so it is for the engine.
var forwarded = []syscall.Signal{syscall.SIGINT, syscall.SIGQUIT, syscall.SIGTERM, syscall.SIGHUP, syscall.SIGTSTP, syscall.SIGCONT}

// runChild runs the engine as zn's child, in a process group of its own with a lifeline (engineLifeline), and returns
// its exit code (128+n for a signal n, as a shell reports it). INT, QUIT, TERM and HUP sent to zn go to the engine's
// whole group. Ctrl-Z (TSTP) stops the engine's group and then zn itself; when zn is continued (CONT), so is the
// engine: the pair stops and goes on together, and the tracker's lock stays held while they are stopped (a zn that
// waits for it says the holder is stopped). A broken standard output (zn list | head -1) is not zn's death: the engine
// meets the broken pipe itself and ends, and zn returns its status.
func runChild(path string, argv, env []string, stdout, stderr io.Writer) (int, error) {
	r, w, err := os.Pipe()
	if err != nil {
		return 0, fmt.Errorf("%w: %v", errNotStarted, err)
	}
	defer w.Close()
	cmd := exec.Command("/bin/sh", append([]string{"-c", engineLifeline, "zn-engine", path}, argv[1:]...)...)
	cmd.Env, cmd.Stdin, cmd.Stdout, cmd.Stderr = env, childStdin, stdout, stderr
	cmd.ExtraFiles = []*os.File{r} // fd 3: the lifeline
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	sigs := make(chan os.Signal, 8)
	for _, s := range forwarded {
		if !signal.Ignored(s) {
			signal.Notify(sigs, s)
		}
	}
	signal.Notify(sigs, syscall.SIGPIPE)
	defer signal.Stop(sigs)
	err = cmd.Start()
	r.Close()
	if err != nil {
		return 0, fmt.Errorf("%w: %v", errNotStarted, err)
	}
	group := cmd.Process.Pid
	done := make(chan struct{})
	go func() { // ends when the engine ends (done is closed after Wait)
		for {
			select {
			case s := <-sigs:
				switch sig := s.(syscall.Signal); sig {
				case syscall.SIGPIPE: // zn's output broke: the engine meets it on its own writes
				case syscall.SIGTSTP:
					syscall.Kill(-group, syscall.SIGTSTP)
					syscall.Kill(os.Getpid(), syscall.SIGSTOP)
				default:
					syscall.Kill(-group, sig)
				}
			case <-done:
				return
			}
		}
	}()
	err = cmd.Wait()
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
// current folder, or ./bin) or lies inside one of roots (a host's folders, its tracker's included) is dropped
// (host.CleanPath, the one PATH cleaner): zn changes folder before the engine starts, into a tracker someone else writes.
func withLuneFirst(env []string, bin string, roots ...string) []string {
	out := make([]string, 0, len(env)+1)
	var entries []string
	for _, e := range env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			if c := host.CleanPath(v, roots...); c != "" {
				entries = strings.Split(c, ":")
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
