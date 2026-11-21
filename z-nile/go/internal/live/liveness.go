package live

import (
	"context"
	"errors"
	"sort"
)

// Wait blocks until an event after since (the worker's seen when nil) wakes the worker, or ctx ends. An open Wait
// counts as heard. It returns a timeout refusal when ctx's deadline passes, and a gone refusal as soon as the
// waiter's own worker is removed (gone, another session registered under its id, or its pid reaped).
func (c *Core) Wait(ctx context.Context, worker string, since *int64) Reply {
	if rep := c.Check(Request{Op: "wait", Worker: worker}); rep != nil {
		return rep
	}
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
	from, myReg := w.Seen, w.Reg
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
			c.hear(w)
		}
		c.mu.Unlock()
	}()
	for {
		c.mu.Lock()
		for _, e := range c.eventsAfter(from, "") {
			// a removal counts only when it ends this registration: one from an earlier registration (--since older than it) does not
			if e.Worker == worker && e.Seq > myReg && (e.Kind == "gone" || (e.Kind == "released" && e.Outcome == "lost")) {
				out := c.refuse("gone", "worker "+worker+" was removed", Reply{"event": e})
				c.mu.Unlock()
				return out
			}
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
			return c.refuse("closed", "the caller went away or the daemon is stopping", nil)
		}
	}
}

// Tick checks every worker's process and silence once. With checkStart it also asks ps once about every live pid:
// a start time that changed means the pid was reused, and a zombie is an ended process. A dead, reused or ended pid
// releases its claim (outcome lost) and removes the worker; a live pid silent for LostAfter becomes lost and keeps
// its claim. Silence is measured on the monotonic clock. A tick that arrives much later than its interval (a laptop
// that slept) gives every worker one fresh interval first. It returns the first storage error.
func (c *Core) Tick(checkStart bool) error {
	type ref struct {
		id  string
		pid int
	}
	c.mu.Lock()
	var refs []ref
	var pids []int
	for _, w := range c.sortedWorkers() {
		refs = append(refs, ref{w.ID, w.PID})
		pids = append(pids, w.PID)
	}
	c.mu.Unlock()
	alive := make(map[int]bool, len(pids))
	for _, p := range pids {
		alive[p] = c.cfg.Probe.Alive(p)
	}
	var procs map[int]Proc
	var perr error
	if checkStart {
		var live []int
		for _, p := range pids {
			if alive[p] {
				live = append(live, p)
			}
		}
		sort.Ints(live)
		procs, perr = c.cfg.Probe.Procs(live)
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	var first error
	keep := func(err error) {
		if err != nil && first == nil {
			first = err
		}
	}
	now := c.cfg.Mono()
	late := c.ticked && c.cfg.TickEvery > 0 && now-c.lastTick > 3*c.cfg.TickEvery
	c.lastTick, c.ticked = now, true
	for _, r := range refs {
		w := c.workers[r.id]
		if w == nil || w.PID != r.pid {
			continue
		}
		gone := !alive[r.pid]
		if p, ok := procs[r.pid]; ok && perr == nil {
			gone = gone || p.Zombie || (w.Start != "" && p.Start != w.Start)
		}
		if gone {
			keep(c.remove(w, "lost"))
			continue
		}
		switch {
		case c.waiters[w.ID] > 0 || late:
			c.hear(w)
		case w.State != "lost" && now-w.heard > c.cfg.LostAfter:
			_, err := c.emit(Event{Kind: "lost", Worker: w.ID})
			keep(err)
		}
	}
	return first
}
