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

// Dial connects to the daemon's socket within two seconds. It refuses a socket owned by another user. A refused
// connection while the socket file exists (a full listen backlog, a daemon about to answer) is retried inside the
// budget; a file that never existed is not.
func Dial(sock string) (net.Conn, error) {
	deadline := time.Now().Add(dialBudget)
	seen := false // the file existed once: a daemon replacing it (unlink, then listen) is waited for
	for {
		st, err := os.Lstat(sock)
		if err != nil {
			if !seen || !errors.Is(err, os.ErrNotExist) || time.Now().Add(10*time.Millisecond).After(deadline) {
				return nil, err
			}
			time.Sleep(10 * time.Millisecond)
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
		retry := errors.Is(err, syscall.ECONNREFUSED) || errors.Is(err, syscall.EAGAIN)
		if !retry || time.Now().Add(10*time.Millisecond).After(deadline) {
			return nil, err
		}
		time.Sleep(10 * time.Millisecond)
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
