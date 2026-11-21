package wire

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"net"
	"time"

	"znile/internal/live"
)

// ErrLost means the daemon closed the connection before it finished its answer.
var ErrLost = errors.New("live daemon connection lost")

// Dial connects to the daemon's socket, giving up after two seconds.
func Dial(sock string) (net.Conn, error) { return net.DialTimeout("unix", sock, 2*time.Second) }

// Result is what a call read: the lines for stdout and how the answer ended.
type Result struct {
	Lines [][]byte
	// Reply is the single reply when the daemon sent one ("ok" present); nil for an event stream.
	Reply live.Reply
	// End is "done" or "timeout" for a stream, or "" after a single reply.
	End string
}

// Call sends one request and reads until the daemon's reply or end line. patience bounds the whole read.
func Call(conn net.Conn, r live.Request, patience time.Duration) (Result, error) {
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
		case probe.OK != nil && r.Op != "events":
			if err := json.Unmarshal(line, &res.Reply); err != nil {
				return res, err
			}
			res.Lines = append(res.Lines, line)
			return res, nil
		default:
			res.Lines = append(res.Lines, line)
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
