// Package web is the live daemon's HTTP face (f0437): the app page, the live state as JSON and a Server-Sent Events
// stream of the daemon's events. It reads a live.Core and changes nothing; the daemon owns the listener's lifetime.
// Only loopback is ever served, and only to a page the daemon itself served (Host and Origin checks, no CORS).
package web

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"znile/internal/live"
)

// DefaultHeartbeat is how often an idle event stream sends a comment, so a dead connection is noticed.
const DefaultHeartbeat = 15 * time.Second

// Handler answers the app's three GET paths from a Core.
type Handler struct {
	Core      *live.Core
	PagePath  string        // the app page, read from disk at each request; empty means none
	Addr      string        // host:port the listener answers on; the Host and Origin checks are built from it
	Heartbeat time.Duration // 0 means DefaultHeartbeat

	mu   sync.RWMutex
	open atomic.Int64
}

// SetPage changes the page file the next request reads.
func (h *Handler) SetPage(path string) {
	h.mu.Lock()
	h.PagePath = path
	h.mu.Unlock()
}

// Open returns the number of requests being answered (an event stream counts until it ends).
func (h *Handler) Open() int { return int(h.open.Load()) }

// Listen opens a TCP listener on 127.0.0.1 only, on the port (0 picks a free one).
func Listen(port int) (net.Listener, error) {
	if port < 0 || port > 65535 {
		return nil, fmt.Errorf("port %d is not between 0 and 65535", port)
	}
	return net.Listen("tcp4", net.JoinHostPort("127.0.0.1", strconv.Itoa(port)))
}

// Serve answers on ln until ctx ends, then closes the listener, ends every event stream and waits a moment for the
// rest. It sets Addr from the listener when Addr is empty.
func (h *Handler) Serve(ctx context.Context, ln net.Listener) error {
	if h.Addr == "" {
		h.Addr = ln.Addr().String()
	}
	srv := &http.Server{Handler: h, ReadHeaderTimeout: 5 * time.Second, BaseContext: func(net.Listener) context.Context { return ctx }}
	done := make(chan struct{})
	go func() { // owner: Serve; ends when ctx ends or Serve returns
		select {
		case <-ctx.Done():
		case <-done:
		}
		sctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if srv.Shutdown(sctx) != nil {
			srv.Close()
		}
	}()
	err := srv.Serve(ln)
	close(done)
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}

// allowed reports whether a Host header names this listener.
func (h *Handler) allowed(host string) bool {
	_, port, err := net.SplitHostPort(h.Addr)
	if err != nil {
		return false
	}
	host = strings.ToLower(host)
	return host == "127.0.0.1:"+port || host == "localhost:"+port
}

func (h *Handler) refuse(w http.ResponseWriter, code int, why string) {
	w.Header().Set("Cache-Control", "no-store")
	http.Error(w, why, code)
}

// ServeHTTP checks the request is a same-origin GET, then routes it.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.open.Add(1)
	defer h.open.Add(-1)
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		h.refuse(w, http.StatusMethodNotAllowed, "this step of the app answers GET only")
		return
	}
	if !h.allowed(r.Host) {
		h.refuse(w, http.StatusForbidden, "the app answers only to Host 127.0.0.1:PORT or localhost:PORT of its own port")
		return
	}
	if o := r.Header.Get("Origin"); o != "" {
		u := strings.ToLower(o)
		if !strings.HasPrefix(u, "http://") || !h.allowed(strings.TrimPrefix(u, "http://")) {
			h.refuse(w, http.StatusForbidden, "the app answers only to a page it served itself (Origin "+o+" is not it)")
			return
		}
	}
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Referrer-Policy", "no-referrer")
	switch r.URL.Path {
	case "/":
		h.page(w)
	case "/api/state":
		h.state(w)
	case "/api/events":
		h.events(w, r)
	default:
		http.NotFound(w, r)
	}
}

func (h *Handler) page(w http.ResponseWriter) {
	h.mu.RLock()
	path := h.PagePath
	h.mu.RUnlock()
	if path == "" {
		h.refuse(w, http.StatusNotFound, "no app page is configured")
		return
	}
	b, err := os.ReadFile(path)
	if err != nil {
		h.refuse(w, http.StatusNotFound, "the app page "+path+" cannot be read: "+err.Error())
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write(b)
}

// holds is what a worker holds right now.
type holds struct {
	Unit     string  `json:"unit"`
	Activity string  `json:"activity"`
	Action   string  `json:"action,omitempty"`
	Step     string  `json:"step,omitempty"`
	Since    float64 `json:"since"`
}

// workerView is one worker as the app reads it.
type workerView struct {
	ID        string   `json:"id"`
	CLI       string   `json:"cli"`
	State     string   `json:"state"` // idle, working or lost
	Mode      string   `json:"mode"`
	Host      string   `json:"host,omitempty"`
	PID       int      `json:"pid"`
	Started   float64  `json:"started"`
	Heard     float64  `json:"heard"`
	LostSince float64  `json:"lost_since,omitempty"`
	Stop      bool     `json:"stop,omitempty"`
	Can       []string `json:"can"`
	Holds     *holds   `json:"holds"`
}

// stateView is the whole of /api/state.
type stateView struct {
	Seq     int64         `json:"seq"`
	Now     float64       `json:"now"`
	Workers []workerView  `json:"workers"`
	Claims  []*live.Claim `json:"claims"`
}

func (h *Handler) state(w http.ResponseWriter) {
	snap := h.Core.Snapshot()
	by := map[string]*live.Claim{}
	for _, c := range snap.Claims {
		by[c.Worker] = c
	}
	v := stateView{Seq: snap.Seq, Now: float64(time.Now().UnixMilli()) / 1000, Workers: []workerView{}, Claims: snap.Claims}
	for _, wk := range snap.Workers {
		wv := workerView{ID: wk.ID, CLI: wk.CLI, State: wk.State, Mode: wk.Mode, Host: wk.Host, PID: wk.PID, Started: wk.Started,
			Heard: wk.Heard, LostSince: wk.LostSince, Stop: wk.Stop, Can: wk.Can}
		if wv.Can == nil {
			wv.Can = []string{}
		}
		if c := by[wk.ID]; c != nil {
			wv.Holds = &holds{Unit: c.Unit, Activity: c.Activity, Action: c.Action, Step: c.Step, Since: c.Since}
		}
		v.Workers = append(v.Workers, wv)
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(v)
}

// events streams one message per daemon event after the connection opened, woken by the Core's own notification (the one
// `wait` and `events --follow` use), with a comment every heartbeat while nothing happens. The first message, kind
// "hello", carries the seq the stream starts after.
func (h *Handler) events(w http.ResponseWriter, r *http.Request) {
	fl, ok := w.(http.Flusher)
	if !ok {
		h.refuse(w, http.StatusInternalServerError, "this connection cannot stream")
		return
	}
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	since := h.Core.Seq()
	fmt.Fprintf(w, "data: {\"kind\":\"hello\",\"seq\":%d}\n\n", since)
	fl.Flush()
	hb := h.Heartbeat
	if hb <= 0 {
		hb = DefaultHeartbeat
	}
	for {
		ctx, cancel := context.WithTimeout(r.Context(), hb)
		evs, err := h.Core.Next(ctx, since, "")
		cancel()
		if err != nil {
			if r.Context().Err() != nil {
				return
			}
			if _, err := fmt.Fprint(w, ": ping\n\n"); err != nil {
				return
			}
			fl.Flush()
			continue
		}
		for _, e := range evs {
			b, err := json.Marshal(e)
			if err != nil {
				return
			}
			if _, err := fmt.Fprintf(w, "data: %s\n\n", b); err != nil {
				return
			}
			since = e.Seq
		}
		fl.Flush()
	}
}
