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

// engineShell runs the lifeline (a test names one that cannot start).
var engineShell = "/bin/sh"

// stopGroup stops zn when the engine's group stopped; TestMain swaps in a guard, so no test stops its own process.
var stopGroup = stopOwnGroup

func stopOwnGroup() { syscall.Kill(os.Getpid(), syscall.SIGSTOP) }

// errNotStarted marks a child that never ran (a noexec mount, a missing shell), unlike one that ran and failed.
var errNotStarted = errors.New("the engine could not be started")

// engineLifeline runs "$@" (the engine) in the shell's foreground, beside a watcher of fd 3 in the background: a pipe
// whose only write end zn holds. When zn ends, however it ends (SIGKILL, or SIGPIPE on its output), the pipe closes and
// the watcher kills the whole process group, the engine's git children included. The engine keeps zn's standard input
// and default signal dispositions (a background command of a non-interactive shell would ignore INT and QUIT). A
// watcher killed by itself leaves the engine without a lifeline (accepted, see the ticket).
const engineLifeline = `{ read -r _ <&3; kill -KILL 0; } </dev/null >/dev/null 2>&1 &
w=$!
exec 3<&-
"$@"
s=$?
kill "$w" 2>/dev/null
exit "$s"`

// noTerminal is the line the lifeline starts with when zn's standard input is not a terminal: the engine's group is
// then never the terminal's foreground group, so a program of it that reads or sets /dev/tty (a login or passphrase
// prompt) fails at once, with its own words, instead of stopping the whole group.
const noTerminal = "trap '' TTIN TTOU\n"

// forwarded are the signals zn passes to the engine's process group when they are sent to zn itself (kill, a
// supervisor). With a terminal, the terminal sends Ctrl-C, Ctrl-\ and Ctrl-Z to the engine's group, its foreground
// group, and not to zn, so each arrives once. A signal ignored when zn started (nohup's HUP) is left ignored, and so it
// is for the engine.
var forwarded = []syscall.Signal{syscall.SIGINT, syscall.SIGQUIT, syscall.SIGTERM, syscall.SIGHUP, syscall.SIGTSTP}

// runChild runs the engine as zn's child, in a process group of its own with a lifeline (engineLifeline), and returns
// its exit code (128+n for a signal n, as a shell reports it).
//
// When zn's standard input is a terminal, the engine's group is made the terminal's foreground group, so git's and
// ssh's prompts on /dev/tty work and Ctrl-C, Ctrl-\ and Ctrl-Z reach the engine; zn takes the terminal back when the
// engine ends. Ctrl-Z stops the engine's group; zn sees it stop, takes the terminal back and stops itself, so the shell
// gets its job back; when zn is continued (fg), it gives the terminal to the engine's group again and continues it. The
// tracker's lock stays held while they are stopped (a zn that waits for it says the holder is stopped). With no
// terminal, a prompt fails at once (noTerminal) and a TSTP sent to zn stops the pair the same way.
//
// A broken standard output (zn list | head -1) is not zn's death: zn catches SIGPIPE, stops reading the engine's
// output, and the engine meets the broken pipe on its next write and ends; an engine that had already ended well is
// reported as 141, as a shell reports a pipeline cut short.
func runChild(path string, argv, env []string, stdout, stderr io.Writer) (int, error) {
	life, lifeW, err := os.Pipe()
	if err != nil {
		return 0, fmt.Errorf("%w: %v", errNotStarted, err)
	}
	defer lifeW.Close()
	outR, outW, err := os.Pipe()
	if err != nil {
		life.Close()
		return 0, fmt.Errorf("%w: %v", errNotStarted, err)
	}
	errR, errW, err := os.Pipe()
	if err != nil {
		life.Close()
		outR.Close()
		outW.Close()
		return 0, fmt.Errorf("%w: %v", errNotStarted, err)
	}
	tty := -1
	if f, ok := childStdin.(*os.File); ok && isTerminal(int(f.Fd())) {
		tty = int(f.Fd())
	}
	lifeline := engineLifeline
	if tty < 0 {
		lifeline = noTerminal + lifeline
	}
	cmd := exec.Command(engineShell, append([]string{"-c", lifeline, "zn-engine", path}, argv[1:]...)...)
	cmd.Env, cmd.Stdin, cmd.Stdout, cmd.Stderr = env, childStdin, outW, errW
	cmd.ExtraFiles = []*os.File{life} // fd 3: the lifeline
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	if tty >= 0 {
		cmd.SysProcAttr.Foreground, cmd.SysProcAttr.Ctty = true, 0 // the child's fd 0 is the terminal
	}
	sigs := make(chan os.Signal, 8)
	for _, s := range forwarded {
		if !signal.Ignored(s) {
			signal.Notify(sigs, s)
		}
	}
	signal.Notify(sigs, syscall.SIGPIPE)
	defer signal.Stop(sigs)
	if tty >= 0 { // zn, in the background while the engine runs, sets the foreground group back: never stopped for it
		signal.Ignore(syscall.SIGTTOU)
		defer signal.Reset(syscall.SIGTTOU)
	}
	err = cmd.Start()
	life.Close()
	outW.Close()
	errW.Close()
	if err != nil {
		outR.Close()
		errR.Close()
		return 0, fmt.Errorf("%w: %v", errNotStarted, err)
	}
	group := cmd.Process.Pid
	copied := make(chan error, 2)
	copyOut := func(w io.Writer, r *os.File) { // ends when the engine's side closes, or the destination breaks
		_, err := io.Copy(w, r)
		r.Close() // a broken destination: the engine meets the broken pipe on its next write
		copied <- err
	}
	go copyOut(stdout, outR)
	go copyOut(stderr, errR)
	done := make(chan struct{})
	go func() { // ends when the engine ends (done is closed after its wait)
		for {
			select {
			case s := <-sigs:
				if sig := s.(syscall.Signal); sig != syscall.SIGPIPE { // zn's output broke: the copier has closed
					syscall.Kill(-group, sig)
				}
			case <-done:
				return
			}
		}
	}()
	ws, err := waitFollowingStops(group, tty)
	close(done)
	if tty >= 0 {
		tcsetpgrp(tty, syscall.Getpgrp())
	}
	var copyErr error
	for i := 0; i < 2; i++ {
		select {
		case e := <-copied:
			if e != nil && copyErr == nil {
				copyErr = e
			}
		case <-time.After(2 * time.Second): // a program the engine left running holds its output: stop reading
			outR.Close()
			errR.Close()
			i = 2
		}
	}
	if err != nil {
		return 0, err
	}
	code := ws.ExitStatus()
	if ws.Signaled() {
		code = 128 + int(ws.Signal())
	}
	if code == 0 && errors.Is(copyErr, syscall.EPIPE) {
		return 141, nil
	}
	return code, nil
}

// waitFollowingStops waits for the engine's runner to end, following its stops: when its group stops (Ctrl-Z, or a
// TSTP forwarded), zn takes the terminal back (when it has one), stops itself, and once continued gives the terminal
// to the engine's group again and continues it.
func waitFollowingStops(pid, tty int) (syscall.WaitStatus, error) {
	for {
		var ws syscall.WaitStatus
		_, err := syscall.Wait4(pid, &ws, syscall.WUNTRACED, nil)
		if errors.Is(err, syscall.EINTR) {
			continue
		}
		if err != nil {
			return ws, err
		}
		if !ws.Stopped() {
			return ws, nil
		}
		if tty >= 0 {
			tcsetpgrp(tty, syscall.Getpgrp())
		}
		stopGroup() // returns once zn is continued
		if tty >= 0 {
			tcsetpgrp(tty, pid)
		}
		syscall.Kill(-pid, syscall.SIGCONT)
	}
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
