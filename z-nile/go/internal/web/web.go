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
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"znile/internal/live"
)

// csp is the policy of every answer. The mockup's own inline script and styles are why script-src and style-src keep
// 'unsafe-inline' in this step; the data layer is the external /live.js.
const csp = "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline' https://fonts.googleapis.com; " +
	"font-src https://fonts.gstatic.com; connect-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"

// DefaultHeartbeat is how often an idle event stream sends a comment, so a dead connection is noticed.
const DefaultHeartbeat = 15 * time.Second

// Handler answers the app's three GET paths from a Core.
type Handler struct {
	Core      *live.Core
	PagePath  string        // the app page, read from disk at each request; empty means none
	Fallback  string        // the page that answers when PagePath cannot be read (the main checkout's); empty means none
	Pages     Pages         // what may be served as the app
	Addr      string        // host:port the listener answers on; the Host and Origin checks are built from it
	Heartbeat time.Duration // 0 means DefaultHeartbeat

	IdleTimeout  time.Duration // an idle keep-alive connection closes after it; 0 means 60 s
	MaxConns     int           // open connections; 0 means 64
	MaxStreams   int           // open event streams; 0 means 16
	WriteTimeout time.Duration // an event stream's write must finish within it; 0 means 10 s

	mu      sync.RWMutex
	open    atomic.Int64
	streams atomic.Int64
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
	idle := h.IdleTimeout
	if idle <= 0 {
		idle = 60 * time.Second
	}
	conns := h.MaxConns
	if conns <= 0 {
		conns = 64
	}
	ln = limitListener(ln, conns)
	srv := &http.Server{Handler: h, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: idle, MaxHeaderBytes: 16 << 10,
		BaseContext: func(net.Listener) context.Context { return ctx }}
	done, fin := make(chan struct{}), make(chan struct{})
	go func() { // owner: Serve; ends when ctx ends or Serve returns, and Serve waits for it
		defer close(fin)
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
	<-fin // every handler has ended (the context ended the event streams) before the daemon goes on
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
	hd := w.Header()
	hd.Set("Cache-Control", "no-store")
	hd.Set("X-Content-Type-Options", "nosniff")
	hd.Set("Referrer-Policy", "no-referrer")
	hd.Set("X-Frame-Options", "DENY")
	hd.Set("Content-Security-Policy", csp)
	if r.Method != http.MethodGet {
		w.Header().Set("Allow", "GET")
		h.refuse(w, http.StatusMethodNotAllowed, "this step of the app answers GET only")
		return
	}
	if !h.allowed(r.Host) {
		h.refuse(w, http.StatusForbidden, "the app answers only to Host 127.0.0.1:PORT or localhost:PORT of its own port")
		return
	}
	if site := r.Header.Get("Sec-Fetch-Site"); site == "cross-site" || site == "same-site" {
		h.refuse(w, http.StatusForbidden, "the app answers only to a page it served itself (Sec-Fetch-Site "+site+")")
		return
	}
	if o := r.Header.Get("Origin"); o != "" {
		u := strings.ToLower(o)
		if !strings.HasPrefix(u, "http://") || !h.allowed(strings.TrimPrefix(u, "http://")) {
			h.refuse(w, http.StatusForbidden, "the app answers only to a page it served itself (Origin "+o+" is not it)")
			return
		}
	}
	switch r.URL.Path {
	case "/":
		h.asset(w, "index.html", "text/html; charset=utf-8")
	case "/live.js":
		h.asset(w, "live.js", "text/javascript; charset=utf-8")
	case "/api/state":
		h.state(w)
	case "/api/events":
		h.events(w, r)
	default:
		http.NotFound(w, r)
	}
}

// asset answers with an app file: the page (index.html) or a file beside it (live.js), from the page the daemon was told
// to serve, else from the fallback. A refusal says which rule failed, never where the file is.
func (h *Handler) asset(w http.ResponseWriter, name, ctype string) {
	h.mu.RLock()
	bases := []string{h.PagePath, h.Fallback}
	h.mu.RUnlock()
	// the page and its script come from one base folder: a base whose live.js is missing or refused is skipped whole, so a
	// worktree's page never runs the main checkout's script
	for _, base := range bases {
		if base == "" {
			continue
		}
		script := filepath.Join(filepath.Dir(base), "live.js")
		if _, err := h.Pages.Resolve(script, "live.js"); err != nil {
			continue
		}
		p := base
		if name != "index.html" {
			p = script
		}
		if b, err := h.Pages.Read(p, name); err == nil {
			w.Header().Set("Content-Type", ctype)
			w.Write(b)
			return
		}
	}
	h.refuse(w, http.StatusNotFound, "the app page is not available")
}

// holds is what a worker holds right now.
type holds struct {
	Unit     string  `json:"unit"`
	Activity string  `json:"activity"`
	Action   string  `json:"action,omitempty"`
	Step     string  `json:"step,omitempty"`
	Since    float64 `json:"since"`
}

// workerView is one worker as the page shows it: no host name, pid or session.
type workerView struct {
	ID        string   `json:"id"`
	CLI       string   `json:"cli"`
	State     string   `json:"state"` // idle, working or lost
	Mode      string   `json:"mode"`
	Account   string   `json:"account,omitempty"` // the owner's label for this terminal's AI account, when it set one
	Started   float64  `json:"started"`
	Heard     float64  `json:"heard"`
	LostSince float64  `json:"lost_since,omitempty"`
	Stop      bool     `json:"stop,omitempty"`
	Can       []string `json:"can"`
	Holds     *holds   `json:"holds"`
}

// claimView is one claim as the page shows it: the unit, the activity, who holds it and since when.
type claimView struct {
	Unit     string  `json:"unit"`
	Activity string  `json:"activity"`
	Step     string  `json:"step,omitempty"`
	Worker   string  `json:"worker"`
	Since    float64 `json:"since"`
}

// eventView is one event as the feed shows it; the host, the pid, the reason and the reference stay in the daemon.
type eventView struct {
	Seq      int64   `json:"seq"`
	At       float64 `json:"at"`
	Kind     string  `json:"kind"`
	Worker   string  `json:"worker,omitempty"`
	CLI      string  `json:"cli,omitempty"`
	Unit     string  `json:"unit,omitempty"`
	Activity string  `json:"activity,omitempty"`
	Action   string  `json:"action,omitempty"`
	Step     string  `json:"step,omitempty"`
	Outcome  string  `json:"outcome,omitempty"`
}

// stateView is the whole of /api/state.
type stateView struct {
	Seq     int64        `json:"seq"`
	Now     float64      `json:"now"`
	Workers []workerView `json:"workers"`
	Claims  []claimView  `json:"claims"`
}

func (h *Handler) state(w http.ResponseWriter) {
	snap := h.Core.Snapshot()
	by := map[string]*live.Claim{}
	v := stateView{Seq: snap.Seq, Now: float64(time.Now().UnixMilli()) / 1000, Workers: []workerView{}, Claims: []claimView{}}
	for _, c := range snap.Claims {
		by[c.Worker] = c
		v.Claims = append(v.Claims, claimView{Unit: c.Unit, Activity: c.Activity, Step: c.Step, Worker: c.Worker, Since: c.Since})
	}
	for _, wk := range snap.Workers {
		wv := workerView{ID: wk.ID, CLI: wk.CLI, State: wk.State, Mode: wk.Mode, Account: wk.Account, Started: wk.Started,
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
// "hello", carries the seq the stream starts after. At most MaxStreams streams are open; every write must finish within
// WriteTimeout, so a reader that stops reading is dropped (a server-wide write timeout would end the healthy streams too).
func (h *Handler) events(w http.ResponseWriter, r *http.Request) {
	limit := h.MaxStreams
	if limit <= 0 {
		limit = 16
	}
	if h.streams.Add(1) > int64(limit) {
		h.streams.Add(-1)
		h.refuse(w, http.StatusServiceUnavailable, fmt.Sprintf("too many event streams are open (the limit of %d); close another tab", limit))
		return
	}
	defer h.streams.Add(-1)
	fl, ok := w.(http.Flusher)
	if !ok {
		h.refuse(w, http.StatusInternalServerError, "this connection cannot stream")
		return
	}
	wt := h.WriteTimeout
	if wt <= 0 {
		wt = 10 * time.Second
	}
	rc := http.NewResponseController(w)
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("X-Accel-Buffering", "no")
	w.WriteHeader(http.StatusOK)
	since := h.Core.Seq()
	rc.SetWriteDeadline(time.Now().Add(wt))
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
			rc.SetWriteDeadline(time.Now().Add(wt))
			if _, err := fmt.Fprint(w, ": ping\n\n"); err != nil {
				return
			}
			fl.Flush()
			rc.SetWriteDeadline(time.Time{})
			continue
		}
		rc.SetWriteDeadline(time.Now().Add(wt))
		for _, e := range evs {
			b, err := json.Marshal(eventView{Seq: e.Seq, At: e.At, Kind: e.Kind, Worker: e.Worker, CLI: e.CLI, Unit: e.Unit,
				Activity: e.Activity, Action: e.Action, Step: e.Step, Outcome: e.Outcome})
			if err != nil {
				return
			}
			if _, err := fmt.Fprintf(w, "data: %s\n\n", b); err != nil {
				return
			}
			since = e.Seq
		}
		fl.Flush()
		rc.SetWriteDeadline(time.Time{})
	}
}
