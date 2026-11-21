package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"syscall"
	"time"
)

const tsFmt = "2006-01-02T15:04:05.000Z07:00"

// Event is one append-only record. Beats are not events.
type Event struct {
	Seq      int64    `json:"seq"`
	Time     string   `json:"time"`
	Kind     string   `json:"kind"`
	Worker   string   `json:"worker,omitempty"`
	CLI      string   `json:"cli,omitempty"`
	Unit     string   `json:"unit,omitempty"`
	Activity string   `json:"activity,omitempty"`
	Outcome  string   `json:"outcome,omitempty"`
	Tokens   int64    `json:"tokens,omitempty"`
	Seconds  int64    `json:"seconds,omitempty"`
	Reason   string   `json:"reason,omitempty"`
	Can      []string `json:"can,omitempty"`
}

type Worker struct {
	ID       string   `json:"id"`
	CLI      string   `json:"cli"`
	Can      []string `json:"can"`
	State    string   `json:"state"` // idle working lost
	Unit     string   `json:"unit,omitempty"`
	Activity string   `json:"activity,omitempty"`
	Since    string   `json:"since"`
	Last     string   `json:"last_heard"`
	last     time.Time
}

// Req is the single request shape; unused fields are ignored.
type Req struct {
	Op       string   `json:"op"`
	Worker   string   `json:"worker,omitempty"`
	CLI      string   `json:"cli,omitempty"`
	Can      []string `json:"can,omitempty"`
	Unit     string   `json:"unit,omitempty"`
	Activity string   `json:"activity,omitempty"`
	Needs    string   `json:"needs,omitempty"`
	Outcome  string   `json:"outcome,omitempty"`
	Tokens   int64    `json:"tokens,omitempty"`
	Seconds  int64    `json:"seconds,omitempty"`
	Reason   string   `json:"reason,omitempty"`
	Since    int64    `json:"since,omitempty"`
	Follow   bool     `json:"follow,omitempty"`
}

type Server struct {
	dir       string
	lostAfter time.Duration
	mu        sync.Mutex
	events    []Event
	notify    chan struct{} // closed and replaced on every event
	workers   map[string]*Worker
	claims    map[string]string // unit+"/"+activity -> worker
	log       *os.File
	conns     sync.Map
}

func newServer(dir string, lostAfter time.Duration) *Server {
	return &Server{dir: dir, lostAfter: lostAfter, notify: make(chan struct{}),
		workers: map[string]*Worker{}, claims: map[string]string{}}
}

// apply mutates state for an event (used live and on replay). Caller holds mu.
func (s *Server) apply(e Event, t time.Time) {
	switch e.Kind {
	case "registered":
		s.workers[e.Worker] = &Worker{ID: e.Worker, CLI: e.CLI, Can: e.Can, State: "idle", Since: e.Time, Last: e.Time, last: t}
	case "claimed":
		if w := s.workers[e.Worker]; w != nil {
			w.State, w.Unit, w.Activity, w.Since = "working", e.Unit, e.Activity, e.Time
			s.claims[e.Unit+"/"+e.Activity] = e.Worker
		}
	case "released", "lost":
		if w := s.workers[e.Worker]; w != nil {
			delete(s.claims, w.Unit+"/"+w.Activity)
			w.Unit, w.Activity, w.Since = "", "", e.Time
			w.State = "idle"
			if e.Kind == "lost" {
				w.State = "lost"
			}
		}
	case "gone":
		if w := s.workers[e.Worker]; w != nil {
			delete(s.claims, w.Unit+"/"+w.Activity)
			delete(s.workers, e.Worker)
		}
	}
}

// emit appends, applies, persists and wakes everyone. Caller holds mu.
func (s *Server) emit(e Event) Event {
	now := time.Now()
	e.Seq = int64(len(s.events)) + 1
	e.Time = now.Format(tsFmt)
	s.apply(e, now)
	s.events = append(s.events, e)
	b, _ := json.Marshal(e)
	if s.log != nil {
		s.log.Write(append(b, '\n'))
	}
	close(s.notify)
	s.notify = make(chan struct{})
	return e
}

func (s *Server) replay() error {
	f, err := os.Open(filepath.Join(s.dir, "events.jsonl"))
	if os.IsNotExist(err) {
		return nil
	} else if err != nil {
		return err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		var e Event
		if json.Unmarshal(sc.Bytes(), &e) != nil {
			continue // torn last line after a crash
		}
		s.events = append(s.events, e)
		s.apply(e, time.Now()) // everyone gets a fresh grace period of lost-after
	}
	return nil
}

func (s *Server) serve(ctx context.Context) error {
	if err := os.MkdirAll(s.dir, 0o755); err != nil {
		return err
	}
	lk, err := os.OpenFile(filepath.Join(s.dir, "lock"), os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return err
	}
	defer lk.Close()
	if err := syscall.Flock(int(lk.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		return fmt.Errorf("another daemon holds %s", lk.Name())
	}
	sock := filepath.Join(s.dir, "sock")
	os.Remove(sock) // stale socket from a crash; the flock proves no live daemon owns it
	if err := s.replay(); err != nil {
		return err
	}
	if s.log, err = os.OpenFile(filepath.Join(s.dir, "events.jsonl"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644); err != nil {
		return err
	}
	ln, err := net.Listen("unix", sock)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	go func() {
		<-ctx.Done()
		ln.Close()
		s.conns.Range(func(k, _ any) bool { k.(net.Conn).Close(); return true })
	}()
	go s.reaper(ctx)
	for {
		c, err := ln.Accept()
		if err != nil {
			os.Remove(sock)
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		s.conns.Store(c, true)
		go func() { defer s.conns.Delete(c); defer c.Close(); s.handle(ctx, c) }()
	}
}

func (s *Server) reaper(ctx context.Context) {
	iv := s.lostAfter / 5
	if iv < 200*time.Millisecond {
		iv = 200 * time.Millisecond
	}
	t := time.NewTicker(iv)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case now := <-t.C:
			s.mu.Lock()
			for _, w := range s.workers {
				if w.State != "lost" && now.Sub(w.last) > s.lostAfter {
					s.emit(Event{Kind: "lost", Worker: w.ID, CLI: w.CLI, Unit: w.Unit, Activity: w.Activity})
				}
			}
			s.mu.Unlock()
		}
	}
}

func reply(c net.Conn, v any) {
	b, _ := json.Marshal(v)
	c.Write(append(b, '\n'))
}

func fail(code int, msg string, extra map[string]any) map[string]any {
	m := map[string]any{"ok": false, "code": code, "error": msg}
	for k, v := range extra {
		m[k] = v
	}
	return m
}

func has(l []string, x string) bool {
	for _, v := range l {
		if v == x {
			return true
		}
	}
	return false
}

func (s *Server) handle(ctx context.Context, c net.Conn) {
	line, err := bufio.NewReader(c).ReadBytes('\n')
	if err != nil {
		return
	}
	var r Req
	if json.Unmarshal(line, &r) != nil {
		reply(c, fail(2, "bad json", nil))
		return
	}
	// the client sends nothing more; a read returning means it hung up
	gone := make(chan struct{})
	go func() { c.Read(make([]byte, 1)); close(gone) }()

	switch r.Op {
	case "register":
		s.mu.Lock()
		e := s.emit(Event{Kind: "registered", Worker: r.Worker, CLI: r.CLI, Can: r.Can})
		s.mu.Unlock()
		reply(c, map[string]any{"ok": true, "event": e})
	case "gone":
		s.mu.Lock()
		e := s.emit(Event{Kind: "gone", Worker: r.Worker})
		s.mu.Unlock()
		reply(c, map[string]any{"ok": true, "event": e})
	case "beat":
		s.mu.Lock()
		w := s.workers[r.Worker]
		if w == nil || w.State == "lost" {
			s.mu.Unlock()
			reply(c, fail(6, "unknown or lost worker "+r.Worker+": register again", nil))
			return
		}
		w.last = time.Now()
		w.Last = w.last.Format(tsFmt)
		s.mu.Unlock()
		reply(c, map[string]any{"ok": true})
	case "claim":
		s.mu.Lock()
		w := s.workers[r.Worker]
		key := r.Unit + "/" + r.Activity
		switch {
		case w == nil || w.State == "lost":
			reply(c, fail(6, "unknown or lost worker "+r.Worker, nil))
		case r.Needs != "" && !has(w.Can, r.Needs):
			reply(c, fail(4, "worker cannot deliver "+r.Needs, map[string]any{"can": w.Can}))
		case w.State == "working":
			reply(c, fail(5, "worker already holds a claim", map[string]any{"unit": w.Unit, "activity": w.Activity}))
		case s.claims[key] != "":
			reply(c, fail(3, "held", map[string]any{"holder": s.claims[key]}))
		default:
			e := s.emit(Event{Kind: "claimed", Worker: r.Worker, CLI: w.CLI, Unit: r.Unit, Activity: r.Activity})
			reply(c, map[string]any{"ok": true, "event": e})
		}
		s.mu.Unlock()
	case "release":
		s.mu.Lock()
		w := s.workers[r.Worker]
		if w == nil || w.State != "working" {
			s.mu.Unlock()
			reply(c, fail(6, "worker holds no claim", nil))
			return
		}
		if r.Outcome == "" {
			r.Outcome = "released"
		}
		e := s.emit(Event{Kind: "released", Worker: r.Worker, CLI: w.CLI, Unit: w.Unit, Activity: w.Activity,
			Outcome: r.Outcome, Tokens: r.Tokens, Seconds: r.Seconds})
		s.mu.Unlock()
		reply(c, map[string]any{"ok": true, "event": e})
	case "poke":
		s.mu.Lock()
		e := s.emit(Event{Kind: "poke", Reason: r.Reason})
		s.mu.Unlock()
		reply(c, map[string]any{"ok": true, "event": e})
	case "workers":
		s.mu.Lock()
		var ws []*Worker
		for _, w := range s.workers {
			w.Last = w.last.Format(tsFmt)
			cp := *w
			ws = append(ws, &cp)
		}
		s.mu.Unlock()
		sort.Slice(ws, func(i, j int) bool { return ws[i].ID < ws[j].ID })
		for _, w := range ws {
			reply(c, w)
		}
	case "events", "wait":
		s.stream(ctx, c, gone, r)
	default:
		reply(c, fail(2, "unknown op "+r.Op, nil))
	}
}

// stream serves "events" (backlog, optionally follow) and "wait" (first relevant new event).
func (s *Server) stream(ctx context.Context, c net.Conn, gone chan struct{}, r Req) {
	s.mu.Lock()
	idx := int(r.Since)
	if r.Op == "wait" && r.Since == 0 {
		idx = len(s.events) // only events after now, unless the caller names a seq
	}
	s.mu.Unlock()
	for {
		s.mu.Lock()
		if idx > len(s.events) {
			idx = len(s.events)
		}
		evs := append([]Event(nil), s.events[idx:]...)
		ch := s.notify
		s.mu.Unlock()
		idx += len(evs)
		for _, e := range evs {
			if r.Op == "wait" {
				if e.Worker == r.Worker && e.Kind != "poke" || !has([]string{"released", "lost", "poke", "gone"}, e.Kind) {
					continue
				}
				reply(c, map[string]any{"ok": true, "event": e})
				return
			}
			reply(c, e)
		}
		if r.Op == "events" && !r.Follow {
			return
		}
		select {
		case <-ch:
		case <-gone:
			return
		case <-ctx.Done():
			return
		}
	}
}
