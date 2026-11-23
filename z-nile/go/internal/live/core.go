package live

import (
	"context"
	"fmt"
	"os"
	"sort"
	"sync"
	"time"
)

// DefaultExpireAfter is how long a silent worker keeps its claim (f0420 G14).
const DefaultExpireAfter = 1800 * time.Second

// toldKeep is how long a loss the worker was told of stays in the history.
const toldKeep = 7 * 24 * time.Hour

// Core holds the live state under one mutex. Every op is O(1) map work.
type Core struct {
	mu  sync.Mutex
	cfg Config
	seq int64
	// step 5: the events are trimmed to the current segment; --since reads of older segments come from the store.
	events   []Event
	notify   chan struct{} // closed and replaced on every event
	workers  map[string]*Worker
	claims   map[string]*Claim // by unit
	held     map[string]string // worker -> unit
	waiters  map[string]int    // worker -> open wait calls
	lastTick time.Duration     // monotonic time of the previous Tick; valid when ticked
	ticked   bool
	losses   []*Loss // markers of lost claims, oldest first
}

// New returns an empty Core. A nil Now, Sink or Probe gets a default: the clock, no storage, no process view.
func New(cfg Config) *Core {
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	if cfg.Mono == nil {
		base := time.Now()
		cfg.Mono = func() time.Duration { return time.Since(base) }
	}
	if cfg.Sink == nil {
		cfg.Sink = nullSink{}
	}
	if cfg.Probe == nil {
		cfg.Probe = nullProbe{}
	}
	if cfg.Host == "" {
		cfg.Host, _ = os.Hostname()
	}
	if cfg.LostAfter <= 0 {
		cfg.LostAfter = 900 * time.Second
	}
	if cfg.ExpireAfter <= 0 {
		cfg.ExpireAfter = DefaultExpireAfter
	}
	return &Core{cfg: cfg, notify: make(chan struct{}), workers: map[string]*Worker{},
		claims: map[string]*Claim{}, held: map[string]string{}, waiters: map[string]int{}}
}

type nullSink struct{}

// Append drops the event.
func (nullSink) Append(Event) error { return nil }

type nullProbe struct{}

// Alive says every pid lives.
func (nullProbe) Alive(int) bool { return true }

// Procs knows every pid, with no start time.
func (nullProbe) Procs(pids []int) (map[int]Proc, error) {
	m := map[int]Proc{}
	for _, p := range pids {
		m[p] = Proc{}
	}
	return m, nil
}

func (c *Core) ms() float64 { return float64(c.cfg.Now().UnixMilli()) / 1000 }

// Restore loads a snapshot (may be nil) and every event of the log, applying the events after the snapshot.
// Every worker is heard from now, so nobody is lost before LostAfter has passed.
func (c *Core) Restore(snap *Snapshot, events []Event) {
	c.mu.Lock()
	defer c.mu.Unlock()
	var from int64
	if snap != nil {
		from = snap.Seq
		c.seq = snap.Seq
		for _, w := range snap.Workers {
			cp := *w
			c.workers[w.ID] = &cp
		}
		for _, cl := range snap.Claims {
			cp := *cl
			c.claims[cl.Unit] = &cp
			c.held[cl.Worker] = cl.Unit
		}
		for _, l := range snap.Losses {
			cp := *l
			c.losses = append(c.losses, &cp)
		}
	}
	for _, e := range events {
		c.events = append(c.events, e)
		if e.Seq > from {
			c.apply(e)
		}
		if e.Seq > c.seq {
			c.seq = e.Seq
		}
	}
	for _, w := range c.workers {
		c.hear(w)
	}
}

// hear marks a worker as heard from now.
func (c *Core) hear(w *Worker) {
	w.Heard = c.ms()
	w.heard = c.cfg.Mono()
}

// Seq returns the newest seq.
func (c *Core) Seq() int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.seq
}

// Snapshot returns the current state.
func (c *Core) Snapshot() Snapshot {
	c.mu.Lock()
	defer c.mu.Unlock()
	s := Snapshot{Seq: c.seq, Workers: []*Worker{}, Claims: []*Claim{}}
	for _, w := range c.sortedWorkers() {
		cp := *w
		s.Workers = append(s.Workers, &cp)
	}
	for _, cl := range c.sortedClaims() {
		cp := *cl
		s.Claims = append(s.Claims, &cp)
	}
	for _, l := range c.losses {
		cp := *l
		cp.Holder = ""
		s.Losses = append(s.Losses, &cp)
	}
	return s
}

// Counts returns the number of registered workers and held claims.
func (c *Core) Counts() (workers, claims int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return len(c.workers), len(c.claims)
}

func (c *Core) sortedWorkers() []*Worker {
	out := make([]*Worker, 0, len(c.workers))
	for _, w := range c.workers {
		out = append(out, w)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out
}

func (c *Core) sortedClaims() []*Claim {
	out := make([]*Claim, 0, len(c.claims))
	for _, cl := range c.claims {
		out = append(out, cl)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Unit < out[j].Unit })
	return out
}

// apply mutates the state for an event, live and on replay. The caller holds mu.
func (c *Core) apply(e Event) {
	w := c.workers[e.Worker]
	switch e.Kind {
	case "registered":
		if w == nil {
			w = &Worker{ID: e.Worker, Started: e.At, State: "idle", Host: e.Host, Seen: e.Seq, Reg: e.Seq}
			c.hear(w)
			c.workers[e.Worker] = w
		}
		w.CLI, w.Can, w.PID, w.Start, w.Session, w.Mode, w.Account = e.CLI, e.Can, e.PID, e.Start, e.Session, e.Mode, e.Account
	case "claimed":
		if w == nil {
			return
		}
		c.claims[e.Unit] = &Claim{Unit: e.Unit, Activity: e.Activity, Action: e.Action, Step: e.Step, Needs: e.Needs,
			Limits: e.Limits, Worker: e.Worker, Since: e.At, Tags: e.Tags}
		c.held[e.Worker] = e.Unit
		w.State = "working"
	case "released":
		if u, ok := c.held[e.Worker]; ok {
			if cl := c.claims[u]; cl != nil && marks(e) && e.Seq > c.lossSeq(e.Worker, u) {
				c.addLoss(e, cl, w)
			}
			delete(c.claims, u)
			delete(c.held, e.Worker)
		}
		// an expired claim leaves the worker as it was: quiet (lost) until its next beat revives it
		if w != nil && e.Outcome != "expired" {
			w.State = "idle"
		}
	case "taken-over":
		for _, l := range c.losses {
			if l.Worker == e.Reason && l.Unit == e.Unit && l.TakenBy == "" {
				l.TakenBy = e.Worker
			}
		}
	case "noticed":
		for _, l := range c.losses {
			if l.Worker == e.Worker && l.NoticedAt == 0 && l.Seq < e.Seq {
				l.NoticedAt = e.At
			}
		}
	case "gone":
		if u, ok := c.held[e.Worker]; ok {
			delete(c.claims, u)
			delete(c.held, e.Worker)
		}
		delete(c.workers, e.Worker)
	case "lost":
		if w != nil {
			w.State = "lost"
			w.LostSince = e.At
		}
	case "revived":
		if w != nil {
			w.LostSince = 0
			w.State = c.stateOf(w.ID)
		}
	case "stop":
		if w != nil {
			w.Stop = true
		}
	}
}

// marks reports whether a release is a lost claim: expired, or its worker's process ended. A session replaced by a new one
// of the same id is no loss to announce.
func marks(e Event) bool {
	return e.Outcome == "expired" || (e.Outcome == "lost" && e.Reason != "replaced")
}

// lossSeq is the seq of the newest loss of the unit by the worker (0 for none): a replay of a snapshot's events never adds one twice.
func (c *Core) lossSeq(worker, unit string) int64 {
	var n int64
	for _, l := range c.losses {
		if l.Worker == worker && l.Unit == unit && l.Seq > n {
			n = l.Seq
		}
	}
	return n
}

func (c *Core) addLoss(e Event, cl *Claim, w *Worker) {
	l := &Loss{Worker: e.Worker, Unit: cl.Unit, Activity: cl.Activity, Action: cl.Action, Step: cl.Step, Since: cl.Since,
		At: e.At, Reason: e.Reason, Seq: e.Seq}
	if w != nil {
		l.Session = w.Session
	}
	// told losses older than a week go, by this event's own time so a replay agrees; an untold one stays
	keep := c.losses[:0]
	for _, o := range c.losses {
		if o.NoticedAt != 0 && e.At-o.NoticedAt > toldKeep.Seconds() {
			continue
		}
		keep = append(keep, o)
	}
	c.losses = append(keep, l)
}

// view copies a loss with the unit's current holder. The caller holds mu.
func (c *Core) view(l *Loss) Loss {
	cp := *l
	if cl := c.claims[l.Unit]; cl != nil && cl.Worker != l.Worker {
		cp.Holder = cl.Worker
	}
	return cp
}

// Losses returns the worker's losses, newest last (every worker's when worker is empty).
func (c *Core) Losses(worker string) []Loss {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.lossesOf(worker, false)
}

func (c *Core) lossesOf(worker string, untoldOnly bool) []Loss {
	out := []Loss{}
	for _, l := range c.losses {
		if (worker == "" || l.Worker == worker) && (!untoldOnly || l.NoticedAt == 0) {
			out = append(out, c.view(l))
		}
	}
	return out
}

func (c *Core) stateOf(id string) string {
	if _, ok := c.held[id]; ok {
		return "working"
	}
	return "idle"
}

// emit stores an event, applies it and wakes every waiter. The caller holds mu. A storage error leaves the state unchanged.
func (c *Core) emit(e Event) (Event, error) {
	e.Seq = c.seq + 1
	e.At = c.ms()
	e.Host = c.cfg.Host
	if w := c.workers[e.Worker]; w != nil && e.CLI == "" {
		e.CLI = w.CLI
	}
	if err := c.cfg.Sink.Append(e); err != nil {
		return e, fmt.Errorf("event log: %w", err)
	}
	c.seq = e.Seq
	c.events = append(c.events, e)
	c.apply(e)
	close(c.notify)
	c.notify = make(chan struct{})
	return e, nil
}

// EventsSince returns the events after seq, of the kind when one is named.
func (c *Core) EventsSince(since int64, kind string) []Event {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.eventsAfter(since, kind)
}

func (c *Core) eventsAfter(since int64, kind string) []Event {
	var out []Event
	i := sort.Search(len(c.events), func(i int) bool { return c.events[i].Seq > since })
	for ; i < len(c.events); i++ {
		if e := c.events[i]; e.Seq > since && (kind == "" || e.Kind == kind) {
			out = append(out, e)
		}
	}
	return out
}

// Next blocks until an event of the kind (any kind when empty) follows seq, or ctx ends, and returns every such event.
func (c *Core) Next(ctx context.Context, since int64, kind string) ([]Event, error) {
	for {
		c.mu.Lock()
		evs := c.eventsAfter(since, kind)
		ch := c.notify
		c.mu.Unlock()
		if len(evs) > 0 {
			return evs, nil
		}
		select {
		case <-ch:
		case <-ctx.Done():
			return nil, ctx.Err()
		}
	}
}
