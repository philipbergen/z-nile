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

// markerPrefixes are the variables the bounded runner and the reaper use to mark a process for killing and for
// measuring; a daemon that outlives its starter must carry none of them.
var markerPrefixes = []string{"ZN_BOUNDED_", "ZN_MEASURE", "ZN_RUN_RECORD"}

func daemonEnv(env []string) []string {
	out := make([]string, 0, len(env))
	for _, kv := range env {
		drop := false
		for _, p := range markerPrefixes {
			if strings.HasPrefix(kv, p) {
				drop = true
			}
		}
		if !drop {
			out = append(out, kv)
		}
	}
	return out
}

// lockStart takes <state>/start.lock for at most startBudget; it returns the file (closing it releases the lock).
func lockStart(dir string) (*os.File, error) {
	f, err := os.OpenFile(filepath.Join(dir, "start.lock"), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return nil, err
	}
	deadline := time.Now().Add(startBudget)
	for {
		if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
			return f, nil
		}
		if time.Now().After(deadline) {
			f.Close()
			return nil, errors.New("another client holds the start lock")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// openLog opens <state>/daemon.log for appending, moving a log over logLimit to daemon.log.1 first.
func openLog(dir string) (*os.File, error) {
	p := filepath.Join(dir, "daemon.log")
	if st, err := os.Stat(p); err == nil && st.Size() > logLimit {
		os.Rename(p, p+".1")
	}
	return os.OpenFile(p, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o600)
}

// autostart returns a connection to this state directory's daemon, starting one when none answers: under the start
// lock it dials again (another client may have started it), and otherwise runs `znlive serve` in a new session, with
// stdin and stdout closed, stderr in daemon.log and none of the bounded runner's markers in its environment, then
// dials every 10 ms for two seconds. The daemon's own flags come from the client's (tests shorten them).
func autostart(real string, o *opts) (net.Conn, error) {
	lk, err := lockStart(real)
	if err != nil {
		return nil, err
	}
	defer lk.Close()
	sock, lock := where.ClientSocket(real), filepath.Join(real, "lock")
	if c, err := wire.Dial(sock, lock); err == nil {
		return c, nil
	}
	self, err := os.Executable()
	if err != nil {
		return nil, err
	}
	args := []string{"serve", "--dir", real}
	for _, f := range [][2]string{{"lost-after", o.lostAfter}, {"idle-exit", o.idleExit}, {"tick-every", o.tickEvery},
		{"check-every", o.checkEvery}} {
		if f[1] != "" {
			args = append(args, "--"+f[0], f[1])
		}
	}
	logf, err := openLog(real)
	if err != nil {
		return nil, fmt.Errorf("cannot open the daemon log: %w", err)
	}
	defer logf.Close()
	cmd := exec.Command(self, args...)
	cmd.Env = daemonEnv(os.Environ())
	cmd.Stderr = logf
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	exited := make(chan struct{})
	go func() { // owner: autostart; reaps the child so it never lingers as a zombie, and ends when it exits
		cmd.Wait()
		close(exited)
	}()
	deadline := time.Now().Add(startBudget)
	for {
		c, err := wire.Dial(sock, lock)
		if err == nil {
			return c, nil
		}
		if errors.Is(err, wire.ErrForeign) {
			return nil, err
		}
		select {
		case <-exited: // it ended at once: the log says why (a loser of the one-instance lock is fine, so dial once more)
			if c, err := wire.Dial(sock, lock); err == nil {
				return c, nil
			}
			return nil, fmt.Errorf("the daemon exited at once (see %s)", filepath.Join(real, "daemon.log"))
		default:
		}
		if time.Now().After(deadline) {
			return nil, fmt.Errorf("the daemon did not answer within %s (see %s)", startBudget, filepath.Join(real, "daemon.log"))
		}
		time.Sleep(10 * time.Millisecond)
	}
}
