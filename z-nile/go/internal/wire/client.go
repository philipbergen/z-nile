package wire

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"syscall"
	"time"

	"znile/internal/live"
)

// ErrLost means the daemon closed the connection before it finished its answer.
var ErrLost = errors.New("live daemon connection lost")

// ErrForeign means the socket file belongs to another user.
var ErrForeign = errors.New("the socket file is owned by another user")

const dialBudget = 2 * time.Second

// pause is the wait between two dial attempts. It is a variable only so that the package's own tests can replace
// it with a synchronisation point (export_test.go); nothing else changes it.
var pause = func() { time.Sleep(10 * time.Millisecond) }

// daemonAlive reports whether some process holds the daemon's lock file: a running, starting or stopping daemon
// holds it exclusively, so a shared lock that is granted at once means no daemon is alive. An empty path or a lock
// file that cannot be opened is read as "unknown, assume alive" for an empty path and "no daemon" for a missing file.
func daemonAlive(lock string) bool {
	if lock == "" {
		return true
	}
	f, err := os.Open(lock)
	if err != nil {
		return false
	}
	defer f.Close()
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_SH|syscall.LOCK_NB); err != nil {
		return true // would block: a daemon holds it
	}
	syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
	return false
}

// Dial connects to the daemon's socket within two seconds. It refuses a socket owned by another user. A refused
// connection while the socket file exists is retried inside the budget only while a daemon holds lock (a daemon
// starting or with a full backlog); when nobody holds it (a daemon killed with kill -9 leaves its socket file) Dial
// gives up at once. An empty lock path always retries. A file that never existed is not retried.
func Dial(sock, lock string) (net.Conn, error) {
	deadline := time.Now().Add(dialBudget)
	seen := false // the file existed once: a daemon replacing it (unlink, then listen) is waited for
	for {
		st, err := os.Lstat(sock)
		if err != nil {
			if !seen || !errors.Is(err, os.ErrNotExist) || time.Now().Add(10*time.Millisecond).After(deadline) {
				return nil, err
			}
			pause()
			continue
		}
		seen = true
		if sys, ok := st.Sys().(*syscall.Stat_t); ok && int(sys.Uid) != os.Getuid() {
			return nil, fmt.Errorf("%w: %s", ErrForeign, sock)
		}
		c, err := net.DialTimeout("unix", sock, time.Until(deadline))
		if err == nil {
			return c, nil
		}
		// ENOENT here means the file vanished between the Lstat and the connect: the daemon is replacing it
		// (unlink, then listen), the same case the Lstat branch waits for.
		retry := errors.Is(err, syscall.ECONNREFUSED) || errors.Is(err, syscall.EAGAIN) || errors.Is(err, syscall.ENOENT)
		if !retry || time.Now().Add(10*time.Millisecond).After(deadline) || !daemonAlive(lock) {
			return nil, err
		}
		pause()
	}
}

// Result is what a call read and how the answer ended.
type Result struct {
	// Lines holds a single reply's line; streamed event lines go to the callback instead.
	Lines [][]byte
	// Reply is the single reply when the daemon sent one ("ok" present); nil for an event stream.
	Reply live.Reply
	// End is "done" or "timeout" for a stream, or "" after a single reply.
	End string
}

// Call sends one request and reads until the daemon's reply or end line. patience bounds the whole read. An event
// line (one with no "ok" key) goes to onLine as it arrives, so a follow prints while it runs; onLine may be nil.
func Call(conn net.Conn, r live.Request, patience time.Duration, onLine func([]byte) error) (Result, error) {
	var res Result
	defer conn.Close()
	b, err := json.Marshal(r)
	if err != nil {
		return res, err
	}
	conn.SetWriteDeadline(time.Now().Add(ioTimeout))
	if _, err := conn.Write(append(b, '\n')); err != nil {
		return res, ErrLost
	}
	conn.SetReadDeadline(time.Now().Add(patience))
	br := bufio.NewReaderSize(conn, 1<<16)
	for {
		line, err := br.ReadBytes('\n')
		if err != nil {
			if err == io.EOF || errors.Is(err, net.ErrClosed) {
				return res, ErrLost
			}
			return res, err
		}
		var probe struct {
			End string `json:"end"`
			OK  *bool  `json:"ok"`
		}
		if json.Unmarshal(line, &probe) != nil {
			return res, errors.New("daemon sent a line that is not JSON")
		}
		switch {
		case probe.End != "":
			res.End = probe.End
			return res, nil
		case probe.OK != nil:
			if err := json.Unmarshal(line, &res.Reply); err != nil {
				return res, err
			}
			res.Lines = append(res.Lines, line)
			return res, nil
		default:
			if onLine != nil {
				if err := onLine(line); err != nil {
					return res, err
				}
			}
		}
	}
}

// Patience is how long a call waits for its answer: a wait or a follow can take its whole timeout, anything else
// a few seconds.
func Patience(r live.Request) time.Duration {
	if r.Op == "wait" || (r.Op == "events" && r.Follow) {
		return timeout(r) + ioTimeout
	}
	return ioTimeout * 2
}
