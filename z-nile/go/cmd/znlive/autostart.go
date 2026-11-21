package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"znile/internal/where"
	"znile/internal/wire"
)

const (
	startBudget  = 2 * time.Second
	logLimit     = 1 << 20 // daemon.log is moved to daemon.log.1 at this size
	writeOpsList = "register beat claim release gone stop emit"
)

// writeOp reports whether op may start a daemon: the first write op does, a read op or a poke never does.
func writeOp(op string) bool {
	for _, w := range strings.Fields(writeOpsList) {
		if w == op {
			return true
		}
	}
	return false
}

// daemonEnv is the environment of a daemon an op starts: an allowlist, so it carries nothing of the process that
// started it (no session id, no ZN_* marker the bounded runner or the reaper reads, no TMPDIR of a folder that may be
// deleted). PATH, HOME, USER, LOGNAME, LANG, TZ and LC_*; Go needs nothing else.
func daemonEnv(env []string) []string {
	var out []string
	for _, kv := range env {
		name, _, _ := strings.Cut(kv, "=")
		switch name {
		case "PATH", "HOME", "USER", "LOGNAME", "LANG", "TZ":
			out = append(out, kv)
		default:
			if strings.HasPrefix(name, "LC_") {
				out = append(out, kv)
			}
		}
	}
	return out
}

// openLog opens <state>/daemon.log for appending, moving a log over logLimit to daemon.log.1 first.
func openLog(dir string) (*os.File, error) {
	p := filepath.Join(dir, "daemon.log")
	if st, err := os.Stat(p); err == nil && st.Size() > logLimit {
		os.Rename(p, p+".1")
	}
	return os.OpenFile(p, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
}

// drainWait is how long a client waits for a daemon that is exiting (it holds <state>/lock until it has finished) to let
// go: an upgrade drains for up to 6 s, so ten seconds cover it with room.
const drainWait = 10 * time.Second

// autostart returns a connection to this state directory's daemon, starting one when none answers. There is no start lock:
// the daemon's own instance lock (<state>/lock) lets exactly one `serve` live, and every loser exits at once. A client runs
// `znlive serve` in a new session with stdin and stdout closed, stderr in daemon.log and the allowlisted environment, then
// dials every 10 ms for two seconds. When its serve exits while <state>/lock is still held (the winner of a race, still
// starting, or the old daemon draining), it keeps dialling for up to drainWait, and the moment the lock is free and nobody
// answers it starts one more. The daemon's flags come from the client's own only for a named state directory (tests).
func autostart(real string, o *opts, named bool) (net.Conn, error) {
	lock := filepath.Join(real, "lock")
	self, err := os.Executable()
	if err != nil {
		return nil, err
	}
	sockDir, err := where.SocketDir(named, os.Getenv("ZN_LIVE_SOCKDIR"))
	if err != nil {
		return nil, fmt.Errorf("no folder for the socket: %w", err)
	}
	args := []string{"serve", "--dir", real, "--sock-dir", sockDir}
	if named {
		for _, f := range [][2]string{{"lost-after", o.lostAfter}, {"idle-exit", o.idleExit}, {"tick-every", o.tickEvery},
			{"check-every", o.checkEvery}} {
			if f[1] != "" {
				args = append(args, "--"+f[0], f[1])
			}
		}
	}
	logPath := filepath.Join(real, "daemon.log")
	for attempt := 0; attempt < 2; attempt++ {
		logf, err := openLog(real)
		if err != nil {
			return nil, fmt.Errorf("cannot open the daemon log: %w", err)
		}
		cmd := exec.Command(self, args...)
		cmd.Env = daemonEnv(os.Environ())
		cmd.Stderr = logf
		cmd.Dir = "/"
		cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
		err = cmd.Start()
		logf.Close()
		if err != nil {
			return nil, err
		}
		exited := make(chan struct{})
		go func() { // owner: autostart; reaps the child so it never lingers as a zombie, and ends when it exits
			cmd.Wait()
			close(exited)
		}()
		deadline := time.Now().Add(startBudget)
		draining := false
		for {
			c, err := wire.Dial(where.ClientSocket(real), lock)
			if err == nil {
				return c, nil
			}
			if errors.Is(err, wire.ErrForeign) {
				return nil, err
			}
			if !draining {
				select {
				case <-exited:
					draining = true
					deadline = time.Now().Add(drainWait)
				default:
				}
			}
			if draining && !daemonAlive(lock) {
				break // nobody holds the lock and nobody answers: start one more
			}
			if time.Now().After(deadline) {
				if draining {
					return nil, fmt.Errorf("another daemon holds %s but does not answer (see %s)", lock, logPath)
				}
				return nil, fmt.Errorf("the daemon did not answer within %s (see %s)", startBudget, logPath)
			}
			time.Sleep(10 * time.Millisecond)
		}
		if attempt == 1 {
			return nil, fmt.Errorf("the daemon exited at once (see %s)", logPath)
		}
	}
	return nil, errors.New("unreachable")
}

// daemonAlive reports whether some process holds the daemon's lock file (a shared, non-blocking flock that would block).
func daemonAlive(lock string) bool {
	f, err := os.Open(lock)
	if err != nil {
		return false
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_SH|syscall.LOCK_NB); err != nil {
		return true
	}
	syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	return false
}
