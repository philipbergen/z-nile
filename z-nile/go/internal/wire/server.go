// Package wire carries requests between znlive clients and the daemon over a Unix socket, one JSON line each way.
package wire

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"znile/internal/live"
)

const (
	ioTimeout   = 5 * time.Second
	maxRequest  = 1 << 20
	defaultWait = 540
	maxWait     = 3600
)

// Server answers requests from a Core.
type Server struct {
	Core     *live.Core
	Dir      string // the state directory's real path; a request naming another is refused
	Build    string
	SockPath string
	PID      int
	Started  time.Time
	Repaired int
	Skipped  int
	// Shutdown ends the daemon; the shutdown op calls it after its reply.
	Shutdown func()

	open  atomic.Int64
	mu    sync.Mutex
	conns map[net.Conn]struct{}
	wg    sync.WaitGroup
}

// Open returns the number of open connections.
func (s *Server) Open() int { return int(s.open.Load()) }

// Serve accepts connections until ctx ends, then closes them all and returns once every handler has finished.
func (s *Server) Serve(ctx context.Context, ln net.Listener) error {
	s.conns = map[net.Conn]struct{}{}
	stopped := make(chan struct{})
	go func() { // owner: Serve; ends when ctx ends or Serve returns
		select {
		case <-ctx.Done():
		case <-stopped:
		}
		ln.Close()
	}()
	defer close(stopped)
	for {
		c, err := ln.Accept()
		if err != nil {
			s.closeAll()
			s.wg.Wait()
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		s.mu.Lock()
		s.conns[c] = struct{}{}
		s.mu.Unlock()
		s.open.Add(1)
		s.wg.Add(1)
		go func() { // owner: Serve; ends when the connection closes
			defer s.wg.Done()
			defer s.open.Add(-1)
			defer func() { s.mu.Lock(); delete(s.conns, c); s.mu.Unlock() }()
			defer c.Close()
			s.handle(ctx, c)
		}()
	}
}

func (s *Server) closeAll() {
	s.mu.Lock()
	defer s.mu.Unlock()
	for c := range s.conns {
		c.Close()
	}
}

func send(c net.Conn, v any) error {
	b, err := json.Marshal(v)
	if err != nil {
		return err
	}
	c.SetWriteDeadline(time.Now().Add(ioTimeout))
	_, err = c.Write(append(b, '\n'))
	return err
}

func (s *Server) handle(ctx context.Context, c net.Conn) {
	c.SetReadDeadline(time.Now().Add(ioTimeout))
	line, err := bufio.NewReaderSize(io.LimitReader(c, maxRequest), 1<<16).ReadBytes('\n')
	if err != nil {
		return
	}
	c.SetReadDeadline(time.Time{})
	var r live.Request
	if err := json.Unmarshal(line, &r); err != nil {
		send(c, live.Reply{"ok": false, "refused": "usage", "why": "request is not JSON"})
		return
	}
	if r.Proto != live.Proto {
		send(c, live.Reply{"ok": false, "refused": "proto", "why": "this daemon speaks protocol 1; the client another"})
		return
	}
	if r.Dir != s.Dir {
		send(c, live.Reply{"ok": false, "refused": "dir", "why": "this daemon serves " + s.Dir})
		return
	}
	// a client sends nothing more, so a read returning means it hung up
	cctx, cancel := context.WithCancel(ctx)
	defer cancel()
	switch r.Op {
	case "wait", "events":
		go func() { // owner: this handler; ends when the connection closes
			io.Copy(io.Discard, c)
			cancel()
		}()
	}
	switch r.Op {
	case "wait":
		s.wait(cctx, c, r)
	case "events":
		s.events(cctx, c, r)
	case "shutdown":
		send(c, live.Reply{"ok": true})
		if s.Shutdown != nil {
			s.Shutdown()
		}
	default:
		rep := s.Core.Do(r)
		if r.Op == "status" && rep.OK() {
			rep["pid"], rep["build"], rep["proto"] = s.PID, s.Build, live.Proto
			rep["uptime"] = time.Since(s.Started).Seconds()
			rep["dir"], rep["socket"] = s.Dir, s.SockPath
			rep["repaired"], rep["skipped"] = s.Repaired, s.Skipped
		}
		send(c, rep)
	}
}

func timeout(r live.Request) time.Duration {
	t := r.Timeout
	if t <= 0 {
		t = defaultWait
	}
	if t > maxWait {
		t = maxWait
	}
	return time.Duration(t * float64(time.Second))
}

func (s *Server) wait(ctx context.Context, c net.Conn, r live.Request) {
	wctx, cancel := context.WithTimeout(ctx, timeout(r))
	defer cancel()
	rep := s.Core.Wait(wctx, r.Worker, r.Since)
	send(c, rep)
}

// events sends the events after since, one per line, then {"end":"done"}, or with follow streams until the timeout
// and ends with {"end":"timeout"}.
func (s *Server) events(ctx context.Context, c net.Conn, r live.Request) {
	since := int64(0)
	if r.Since != nil {
		since = *r.Since
	}
	if !r.Follow {
		for _, e := range s.Core.EventsSince(since, r.Kind) {
			if send(c, e) != nil {
				return
			}
		}
		send(c, map[string]string{"end": "done"})
		return
	}
	fctx, cancel := context.WithTimeout(ctx, timeout(r))
	defer cancel()
	for {
		evs, err := s.Core.Next(fctx, since, r.Kind)
		if err != nil {
			send(c, map[string]string{"end": "timeout"})
			return
		}
		for _, e := range evs {
			if send(c, e) != nil {
				return
			}
			since = e.Seq
		}
	}
}
