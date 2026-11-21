package live

import (
	"context"
	"errors"
	"sort"
)

// Wait blocks until an event after since (the worker's seen when nil) wakes the worker, or ctx ends. An open
// Wait counts as heard. It returns a timeout refusal when ctx's deadline passes.
func (c *Core) Wait(ctx context.Context, worker string, since *int64) Reply {
	c.mu.Lock()
	w := c.workers[worker]
	if w == nil {
		defer c.mu.Unlock()
		return c.refuse("unknown", "no worker "+worker+": register it first", nil)
	}
	if w.Stop { // asked to stop: nothing to wait for
		defer c.mu.Unlock()
		out := Reply{"stop": true}
		for i := len(c.events) - 1; i >= 0; i-- {
			if e := c.events[i]; e.Kind == "stop" && e.Worker == worker {
				out["event"] = e
				break
			}
		}
		return c.reply(out)
	}
	from := w.Seen
	if since != nil {
		from = *since
	}
	c.waiters[worker]++
	if err := c.revive(w); err != nil {
		c.waiters[worker]--
		defer c.mu.Unlock()
		return c.failed(err)
	}
	c.mu.Unlock()
	defer func() {
		c.mu.Lock()
		if c.waiters[worker]--; c.waiters[worker] <= 0 {
			delete(c.waiters, worker)
		}
		if w := c.workers[worker]; w != nil {
			w.Heard = c.ms()
		}
		c.mu.Unlock()
	}()
	for {
		c.mu.Lock()
		for _, e := range c.eventsAfter(from, "") {
			if wakes(e, worker) {
				if w := c.workers[worker]; w != nil && e.Seq > w.Seen {
					w.Seen = e.Seq
				}
				out := c.reply(Reply{"event": e})
				c.mu.Unlock()
				return out
			}
		}
		if n := len(c.events); n > 0 && c.events[n-1].Seq > from {
			from = c.events[n-1].Seq // those were looked at: do not scan them again
		}
		ch := c.notify
		c.mu.Unlock()
		select {
		case <-ch:
		case <-ctx.Done():
			c.mu.Lock()
			defer c.mu.Unlock()
			if errors.Is(ctx.Err(), context.DeadlineExceeded) {
				return c.refuse("timeout", "nothing woke the worker in time", nil)
			}
			return c.refuse("closed", "the caller went away", nil)
		}
	}
}

// Tick checks every worker's process and silence once. With checkStart it also compares each pid's start time,
// which catches a reused pid. A dead or reused pid releases its claim (outcome lost) and removes the worker; a live
// pid silent for LostAfter becomes lost and keeps its claim. It returns the first storage error.
func (c *Core) Tick(checkStart bool) error {
	type ref struct {
		id    string
		pid   int
		start string
	}
	c.mu.Lock()
	var refs []ref
	var pids []int
	for _, w := range c.sortedWorkers() {
		refs = append(refs, ref{w.ID, w.PID, w.Start})
		pids = append(pids, w.PID)
	}
	c.mu.Unlock()
	alive := make(map[int]bool, len(pids))
	for _, p := range pids {
		alive[p] = c.cfg.Probe.Alive(p)
	}
	var starts map[int]string
	if checkStart {
		var live []int
		for _, p := range pids {
			if alive[p] {
				live = append(live, p)
			}
		}
		sort.Ints(live)
		starts = c.cfg.Probe.Starts(live)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	var first error
	keep := func(err error) {
		if err != nil && first == nil {
			first = err
		}
	}
	now := c.ms()
	for _, r := range refs {
		w := c.workers[r.id]
		if w == nil || w.PID != r.pid {
			continue
		}
		reused := false
		if s, ok := starts[r.pid]; ok && w.Start != "" && s != w.Start {
			reused = true
		}
		if !alive[r.pid] || reused {
			keep(c.remove(w, "lost"))
			continue
		}
		if c.waiters[w.ID] > 0 {
			w.Heard = now
		} else if w.State != "lost" && now-w.Heard > c.cfg.LostAfter.Seconds() {
			_, err := c.emit(Event{Kind: "lost", Worker: w.ID})
			keep(err)
		}
	}
	return first
}
