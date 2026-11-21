// Package wire carries requests between znlive clients and the daemon over a Unix socket, one JSON line each way.
package wire

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"znile/internal/live"
)

const (
	ioTimeout   = 5 * time.Second
	drainLimit  = 6 * time.Second // how long a stopping daemon waits for in-flight requests
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
	// App starts serving the app on a TCP port (0: any) from the page file, or returns the address it already serves on.
	App func(port int, page string) (addr string, err error)
	// ExtraOpen counts open connections of other kinds (the app's), so they keep the daemon from idling out.
	ExtraOpen func() int

	open  atomic.Int64
	mu    sync.Mutex
	conns map[net.Conn]struct{}
	wg    sync.WaitGroup
}

// Open returns the number of open connections.
func (s *Server) Open() int {
	n := int(s.open.Load())
	if s.ExtraOpen != nil {
		n += s.ExtraOpen()
	}
	return n
}

// temporary reports an Accept error that a later Accept can get past: out of descriptors or buffers, an aborted
// connection, or a timeout.
func temporary(err error) bool {
	var ne net.Error
	if errors.As(err, &ne) && ne.Timeout() {
		return true
	}
	for _, e := range []error{syscall.EMFILE, syscall.ENFILE, syscall.ENOBUFS, syscall.ENOMEM, syscall.ECONNABORTED} {
		if errors.Is(err, e) {
			return true
		}
	}
	return false
}

// Serve accepts connections until ctx ends. Then the listener closes first, waits and follows end (they watch ctx),
// and the requests already in flight finish, each bounded by its deadline, before Serve returns.
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
	backoff := time.Duration(0)
	for {
		c, err := ln.Accept()
		if err != nil {
			if ctx.Err() == nil && temporary(err) {
				if backoff = min(max(backoff*2, 5*time.Millisecond), time.Second); backoff > 0 {
					select {
					case <-time.After(backoff):
					case <-ctx.Done():
					}
				}
				continue
			}
			s.drain()
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		backoff = 0
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

// drain waits for every handler; one that is still running after drainLimit has its connection closed.
func (s *Server) drain() {
	done := make(chan struct{})
	go func() { s.wg.Wait(); close(done) }() // owner: drain; ends when every handler has
	select {
	case <-done:
		return
	case <-time.After(drainLimit):
	}
	s.mu.Lock()
	for c := range s.conns {
		c.Close()
	}
	s.mu.Unlock()
	<-done
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

func (s *Server) refuse(c net.Conn, word, why string) {
	send(c, live.Reply{"ok": false, "refused": word, "why": why, "seq": s.Core.Seq()})
}

func (s *Server) handle(ctx context.Context, c net.Conn) {
	c.SetReadDeadline(time.Now().Add(ioTimeout))
	line, err := bufio.NewReaderSize(io.LimitReader(c, maxRequest+1), 1<<16).ReadBytes('\n')
	if len(line) > maxRequest {
		s.refuse(c, "usage", "the request is over 1 MB")
		c.SetReadDeadline(time.Now().Add(time.Second))
		io.Copy(io.Discard, io.LimitReader(c, 8<<20)) // let the client finish sending, so it can read the reply
		return
	}
	if err != nil {
		return
	}
	c.SetReadDeadline(time.Time{})
	var r live.Request
	if err := json.Unmarshal(line, &r); err != nil {
		s.refuse(c, "usage", "the request is not JSON")
		return
	}
	if r.Proto != live.Proto {
		s.refuse(c, "proto", "this daemon speaks protocol 1; the client another")
		return
	}
	if r.Dir != s.Dir {
		s.refuse(c, "dir", "this daemon serves "+s.Dir+", not "+r.Dir)
		return
	}
	// a client sends nothing more, so a read returning means it hung up
	cctx, cancel := context.WithCancel(ctx)
	defer cancel()
	switch r.Op {
	case "wait", "events":
		if rep := s.Core.Check(r); rep != nil {
			send(c, rep)
			return
		}
		if r.Op == "events" && r.Worker != "" {
			s.Core.Touch(r.Worker)
		}
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
	case "app":
		if rep := s.Core.Check(r); rep != nil {
			send(c, rep)
			return
		}
		if s.App == nil {
			s.refuse(c, "http", "this daemon cannot serve the app")
			return
		}
		addr, err := s.App(r.Port, r.Page)
		if err != nil {
			s.refuse(c, "http", err.Error())
			return
		}
		send(c, live.Reply{"ok": true, "seq": s.Core.Seq(), "addr": addr, "url": "http://" + addr + "/"})
	case "shutdown":
		_ = send(c, live.Reply{"ok": true, "seq": s.Core.Seq()}) // shut down even if nobody hears the answer
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
		if err := send(c, rep); err != nil {
			return // the client went away; the op is done and every op can be repeated
		}
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
	send(c, s.Core.Wait(wctx, r.Worker, r.Since))
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
