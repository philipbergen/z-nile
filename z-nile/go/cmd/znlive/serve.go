package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	"znile/internal/live"
	"znile/internal/store"
	"znile/internal/where"
	"znile/internal/wire"
)

const (
	defaultLostAfter = 900 * time.Second
	defaultIdleExit  = 30 * time.Minute
	defaultTick      = 2 * time.Second
	defaultCheck     = 5 * time.Second
	startCheckEvery  = 60 * time.Second
	maxCheck         = 10 * time.Second
)

// durationOpt reads a duration flag, else the environment variable (when one is named), else the default.
func durationOpt(o *opts, flagVal, env string, def time.Duration) (time.Duration, error) {
	v := flagVal
	if v == "" && env != "" {
		v = os.Getenv(env)
	}
	if v == "" {
		return def, nil
	}
	d, err := duration(v)
	if err != nil || d <= 0 {
		return 0, fmt.Errorf("bad duration %q", v)
	}
	return d, nil
}

// serve runs the daemon until SIGTERM, shutdown, idle exit or a replaced binary, and writes the snapshot on the way out.
func serve(o *opts, stderr io.Writer) int {
	fail := func(code int, f string, a ...any) int {
		fmt.Fprintf(stderr, "znlive serve: "+f+"\n", a...)
		return code
	}
	lostAfter, e1 := durationOpt(o, o.lostAfter, "ZN_LIVE_LOST_AFTER", defaultLostAfter)
	idleExit, e2 := durationOpt(o, o.idleExit, "ZN_LIVE_IDLE_EXIT", defaultIdleExit)
	tickEvery, e3 := durationOpt(o, o.tickEvery, "", defaultTick)
	checkEvery, e4 := durationOpt(o, o.checkEvery, "", defaultCheck)
	if err := errors.Join(e1, e2, e3, e4); err != nil {
		return fail(exitUsage, "%v", err)
	}
	checkEvery = min(checkEvery, maxCheck)
	dir, named, err := resolveDir(o)
	if err != nil {
		return fail(exitUnavailable, "cannot find the state directory (%v). Run it inside the repository, or pass --dir", err)
	}
	if !named {
		for _, f := range []string{"lost-after", "idle-exit", "tick-every", "check-every"} {
			if o.visited[f] {
				return fail(exitUsage, "--%s configures the shared daemon and is for tests: use it only with a throwaway --dir", f)
			}
		}
	}
	// the daemon belongs to nobody who started it: it works from "/" (a deleted folder cannot hurt it), and its socket
	// folder is the one the starter named, else the default rule's
	if err := os.Chdir("/"); err != nil {
		return fail(exitUnavailable, "cannot change to /: %v", err)
	}
	sockDir := o.sockDir
	if sockDir == "" {
		if sockDir, err = where.SocketDir(named, os.Getenv("ZN_LIVE_SOCKDIR")); err != nil {
			return fail(exitUnavailable, "no folder for the socket: %v", err)
		}
	}
	real, err := where.Prepare(dir)
	if err != nil {
		return fail(exitUnavailable, "cannot prepare %s: %v", dir, err)
	}
	lk, err := os.OpenFile(filepath.Join(real, "lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return fail(exitUnavailable, "%v", err)
	}
	defer lk.Close()
	if err := syscall.Flock(int(lk.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return fail(exitUnavailable, "another daemon already serves %s", real)
	}
	st, snap, events, err := store.Open(real)
	if err != nil {
		return fail(exitUnavailable, "cannot read the event log: %v", err)
	}
	core := live.New(live.Config{Sink: st, Probe: where.OSProbe{}, LostAfter: lostAfter, TickEvery: tickEvery})
	core.Restore(snap, events)
	sock := where.SocketPathIn(sockDir, real)
	os.Remove(sock) // stale from a crash: the flock proves no live daemon owns it
	os.Remove(filepath.Join(real, "http"))
	ln, err := listenPrivate(sock)
	if err != nil {
		st.Close()
		return fail(exitUnavailable, "cannot listen on %s: %v", sock, err)
	}
	if err := writePointer(real, sock); err != nil {
		ln.Close()
		st.Close()
		return fail(exitUnavailable, "cannot write the socket pointer: %v", err)
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	app := &appd{ctx: ctx, core: core, dir: real, stderr: stderr}
	srv := &wire.Server{Core: core, Dir: real, Build: build, SockPath: sock, PID: os.Getpid(), Started: time.Now(),
		Repaired: st.Repaired, Skipped: st.Skipped, Shutdown: stop, App: app.ensure, ExtraOpen: app.open}
	if o.http {
		if _, err := app.ensure(o.port, o.page); err != nil {
			ln.Close()
			st.Close()
			os.Remove(sock)
			return fail(exitUnavailable, "%v", err)
		}
	}
	if err := core.Tick(true); err != nil {
		fmt.Fprintf(stderr, "znlive serve: first liveness check: %v\n", err)
	}
	done := make(chan struct{})
	go func() { // owner: serve; ends when ctx ends
		defer close(done)
		watch(ctx, stop, core, srv, tickEvery, checkEvery, idleExit, stderr, sock, real)
	}()
	fmt.Fprintf(stderr, "znlive serve: build %s pid %d serving %s on %s\n", build, os.Getpid(), real, sock)
	fmt.Fprintf(stderr, "znlive serve: environment names (%d): %s\n", len(os.Environ()), envNames())
	serr := srv.Serve(ctx, ln)
	stop()
	<-done
	app.close()
	code := exitOK
	if err := errors.Join(serr, st.WriteSnapshot(core.Snapshot()), st.Close()); err != nil {
		fmt.Fprintf(stderr, "znlive serve: %v\n", err)
		code = exitUnavailable
	}
	os.Remove(sock)
	return code
}

// listenPrivate listens on a Unix socket created with mode 0600.
func listenPrivate(sock string) (net.Listener, error) {
	old := syscall.Umask(0o077)
	defer syscall.Umask(old)
	ln, err := net.Listen("unix", sock)
	if err != nil {
		return nil, err
	}
	return ln, os.Chmod(sock, 0o600)
}

func writePointer(dir, sock string) error { return writeAtomic(dir, "socket", sock) }

// writeAtomic writes <dir>/<name> holding the line, all or nothing.
func writeAtomic(dir, name, line string) error {
	tmp, err := os.CreateTemp(dir, "."+name+"-*")
	if err != nil {
		return err
	}
	_, werr := tmp.WriteString(line + "\n")
	if err := errors.Join(werr, tmp.Close()); err != nil {
		os.Remove(tmp.Name())
		return err
	}
	return os.Rename(tmp.Name(), filepath.Join(dir, name))
}

// watch runs the periodic work until ctx ends: process checks every tickEvery (start times every minute), and every
// check interval whether the binary was replaced or the daemon has idled for idleExit. It calls stop to end the daemon.
func watch(ctx context.Context, stop func(), core *live.Core, srv *wire.Server, tickEvery, checkEvery, idleExit time.Duration, stderr io.Writer, sock, stateDir string) {
	self, err := os.Executable()
	var first os.FileInfo
	if err == nil {
		first, _ = os.Stat(self)
	}
	// liveness has its own ticker, at exactly tickEvery: sharing one loop with the other checks and skipping a tick that
	// came a hair early made a dead worker wait two ticks half the time
	var wg sync.WaitGroup
	wg.Add(1)
	go func() { // owner: watch; ends when ctx ends, and watch waits for it
		defer wg.Done()
		tk := time.NewTicker(tickEvery)
		defer tk.Stop()
		lastStarts := time.Now()
		for {
			select {
			case <-ctx.Done():
				return
			case at := <-tk.C:
				starts := at.Sub(lastStarts) >= startCheckEvery
				if starts {
					lastStarts = at
				}
				if err := core.Tick(starts); err != nil {
					fmt.Fprintf(stderr, "znlive serve: liveness check: %v\n", err)
				}
			}
		}
	}()
	defer wg.Wait()
	step := min(checkEvery, max(idleExit/4, 20*time.Millisecond))
	t := time.NewTicker(step)
	defer t.Stop()
	now := time.Now()
	lastCheck, idleSince := now, now
	for {
		select {
		case <-ctx.Done():
			return
		case now = <-t.C:
		}
		if w, _ := core.Counts(); w > 0 || srv.Open() > 0 {
			idleSince = now
		} else if now.Sub(idleSince) >= idleExit {
			fmt.Fprintf(stderr, "znlive serve: idle for %s, exiting\n", idleExit)
			stop()
			return
		}
		if now.Sub(lastCheck) >= checkEvery {
			lastCheck = now
			// a daemon nobody can reach (its socket file or its state directory was removed, as a temp cleaner or a
			// deleted folder does) exits, so the next write op starts one that can be reached
			if _, err := os.Lstat(sock); err != nil {
				fmt.Fprintf(stderr, "znlive serve: the socket %s is gone, exiting\n", sock)
				stop()
				return
			}
			if _, err := os.Stat(stateDir); err != nil {
				fmt.Fprintf(stderr, "znlive serve: the state directory %s is gone, exiting\n", stateDir)
				stop()
				return
			}
			if first != nil {
				if cur, err := os.Stat(self); err != nil || !os.SameFile(first, cur) || !cur.ModTime().Equal(first.ModTime()) || cur.Size() != first.Size() {
					fmt.Fprintf(stderr, "znlive serve: the binary %s was replaced, exiting\n", self)
					stop()
					return
				}
			}
		}
	}
}

// envNames lists the names (never the values) of the variables the daemon holds, for the log.
func envNames() string {
	var names []string
	for _, kv := range os.Environ() {
		n, _, _ := strings.Cut(kv, "=")
		names = append(names, n)
	}
	sort.Strings(names)
	return strings.Join(names, ",")
}
