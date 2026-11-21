package live

import (
	"fmt"
	"regexp"
	"sort"
	"strings"
)

var kindRe = regexp.MustCompile(`^[a-z][a-z0-9-]*$`)

// ownKinds are the kinds the ops themselves append; emit refuses them.
var ownKinds = map[string]bool{"registered": true, "claimed": true, "released": true, "gone": true,
	"lost": true, "revived": true, "stop": true, "poke": true}

// wakes reports whether an event of this kind can wake the waiter. A waiter is never woken by its own events,
// and a stop event wakes only the worker it names.
func wakes(e Event, waiter string) bool {
	switch e.Kind {
	case "registered", "claimed", "lost", "revived":
		return false
	case "stop":
		return e.Worker == waiter
	}
	return e.Worker != waiter
}

func (c *Core) reply(r Reply) Reply {
	r["ok"] = true
	r["seq"] = c.seq
	return r
}

func (c *Core) refuse(word, why string, extra Reply) Reply {
	r := Reply{"ok": false, "refused": word, "why": why, "seq": c.seq}
	for k, v := range extra {
		r[k] = v
	}
	return r
}

func (c *Core) usage(why string) Reply { return c.refuse("usage", why, nil) }

func (c *Core) failed(err error) Reply { return c.refuse("storage", err.Error(), nil) }

// Do runs one non-blocking op. Whatever the outcome, a request naming a known worker marks it heard and sets its
// seen to the newest seq, so the next wait starts there.
func (c *Core) Do(r Request) Reply {
	var start string
	if r.Op == "register" && r.PID > 0 {
		start = c.cfg.Probe.Starts([]int{r.PID})[r.PID] // outside the lock: it runs ps
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	out := c.do(r, start)
	// gone and stop act on the named worker from outside: they say nothing about its hearing
	if w := c.workers[r.Worker]; w != nil && r.Op != "gone" && r.Op != "stop" {
		w.Heard = c.ms()
		if c.seq > w.Seen {
			w.Seen = c.seq
		}
	}
	return out
}

func (c *Core) do(r Request, start string) Reply {
	switch r.Op {
	case "register":
		return c.register(r, start)
	case "beat":
		w := c.workers[r.Worker]
		if w == nil {
			return c.refuse("unknown", "no worker "+r.Worker+": register it first", nil)
		}
		if err := c.revive(w); err != nil {
			return c.failed(err)
		}
		return c.reply(Reply{"state": w.State})
	case "claim":
		return c.claim(r)
	case "release":
		return c.release(r)
	case "gone":
		w := c.workers[r.Worker]
		if w == nil {
			return c.refuse("unknown", "no worker "+r.Worker, nil)
		}
		if err := c.remove(w, "back"); err != nil {
			return c.failed(err)
		}
		return c.reply(Reply{})
	case "stop":
		w := c.workers[r.Worker]
		if w == nil {
			return c.refuse("unknown", "no worker "+r.Worker, nil)
		}
		e, err := c.emit(Event{Kind: "stop", Worker: w.ID})
		if err != nil {
			return c.failed(err)
		}
		return c.reply(Reply{"event": e})
	case "workers":
		ws := []*Worker{}
		for _, w := range c.sortedWorkers() {
			cp := *w
			ws = append(ws, &cp)
		}
		return c.reply(Reply{"workers": ws})
	case "claims":
		cs := []*Claim{}
		for _, cl := range c.sortedClaims() {
			cp := *cl
			cs = append(cs, &cp)
		}
		return c.reply(Reply{"claims": cs})
	case "poke":
		if _, err := c.emit(Event{Kind: "poke", Reason: r.Reason, Ref: r.Ref}); err != nil {
			return c.failed(err)
		}
		return c.reply(Reply{})
	case "emit":
		return c.emitOp(r)
	case "status":
		return c.reply(Reply{"workers": len(c.workers), "claims": len(c.claims)})
	}
	return c.usage("unknown op " + r.Op)
}

// revive turns a lost worker back into a working or idle one.
func (c *Core) revive(w *Worker) error {
	if w.State != "lost" {
		return nil
	}
	_, err := c.emit(Event{Kind: "revived", Worker: w.ID})
	return err
}

// remove releases the worker's claim with the outcome, then removes the worker.
func (c *Core) remove(w *Worker, outcome string) error {
	if u, ok := c.held[w.ID]; ok {
		if _, err := c.emit(c.releaseEvent(c.claims[u], outcome)); err != nil {
			return err
		}
	}
	_, err := c.emit(Event{Kind: "gone", Worker: w.ID})
	return err
}

func (c *Core) releaseEvent(cl *Claim, outcome string) Event {
	return Event{Kind: "released", Worker: cl.Worker, Unit: cl.Unit, Activity: cl.Activity, Action: cl.Action,
		Step: cl.Step, Needs: cl.Needs, Limits: cl.Limits, Tags: cl.Tags, Outcome: outcome}
}

func (c *Core) register(r Request, start string) Reply {
	if r.CLI == "" || r.PID <= 0 {
		return c.usage("register needs --cli and --pid")
	}
	switch r.Mode {
	case "", "session", "run", "plain":
	default:
		return c.usage("--mode is session, run or plain")
	}
	for _, a := range r.Can {
		if strings.Count(a, "/") != 1 || strings.HasPrefix(a, "/") || strings.HasSuffix(a, "/") {
			return c.usage("--can takes activity/level, got " + a)
		}
	}
	id := r.Worker
	if id == "" {
		id = fmt.Sprintf("%s-%d@%s", r.CLI, r.PID, c.cfg.Host)
		if r.As != "" {
			id += "." + r.As
		}
	}
	mode := r.Mode
	if mode == "" {
		mode = "plain"
	}
	if old := c.workers[id]; old != nil && old.Session != r.Session {
		if err := c.remove(old, "lost"); err != nil {
			return c.failed(err)
		}
	}
	old := c.workers[id]
	if old != nil && old.CLI == r.CLI && old.PID == r.PID && old.Start == start && old.Mode == mode &&
		strings.Join(old.Can, ",") == strings.Join(r.Can, ",") {
		if err := c.revive(old); err != nil {
			return c.failed(err)
		}
		return c.reply(Reply{"worker": id})
	}
	if _, err := c.emit(Event{Kind: "registered", Worker: id, CLI: r.CLI, PID: r.PID, Start: start,
		Session: r.Session, Mode: mode, Can: r.Can}); err != nil {
		return c.failed(err)
	}
	if w := c.workers[id]; w != nil {
		w.Heard = c.ms()
	}
	return c.reply(Reply{"worker": id})
}

func has(l []string, x string) bool {
	for _, v := range l {
		if v == x {
			return true
		}
	}
	return false
}

func (c *Core) claim(r Request) Reply {
	if r.Unit == "" || r.Activity == "" {
		return c.usage("claim needs --unit and --activity")
	}
	w := c.workers[r.Worker]
	if w == nil {
		return c.refuse("unknown", "no worker "+r.Worker+": register it first", nil)
	}
	if err := c.revive(w); err != nil {
		return c.failed(err)
	}
	if r.Needs != "" && !has(w.Can, r.Needs) {
		return c.refuse("cannot", "worker "+w.ID+" cannot deliver "+r.Needs, Reply{"can": w.Can})
	}
	if u, ok := c.held[w.ID]; ok {
		cl := c.claims[u]
		if u == r.Unit && cl.Activity == r.Activity {
			return c.reply(Reply{"claim": cl, "again": true})
		}
		return c.refuse("busy", fmt.Sprintf("worker %s already holds %s (%s)", w.ID, cl.Unit, cl.Activity),
			Reply{"unit": cl.Unit, "activity": cl.Activity})
	}
	if cl := c.claims[r.Unit]; cl != nil {
		return c.refuse("held", fmt.Sprintf("%s is held by %s for %s", r.Unit, cl.Worker, cl.Activity),
			Reply{"holder": cl.Worker, "unit": cl.Unit, "activity": cl.Activity})
	}
	classes := make([]string, 0, len(r.Limit))
	for class := range r.Limit {
		classes = append(classes, class)
	}
	sort.Strings(classes)
	for _, class := range classes {
		n := 0
		for _, cl := range c.claims {
			if has(cl.Limits, class) {
				n++
			}
		}
		if n >= r.Limit[class] {
			return c.refuse("cap", fmt.Sprintf("%d claims already carry class %s (limit %d)", n, class, r.Limit[class]),
				Reply{"class": class, "limit": r.Limit[class]})
		}
	}
	if _, err := c.emit(Event{Kind: "claimed", Worker: w.ID, Unit: r.Unit, Activity: r.Activity, Action: r.Action,
		Step: r.Step, Needs: r.Needs, Limits: classes, Tags: r.Tags}); err != nil {
		return c.failed(err)
	}
	return c.reply(Reply{"claim": c.claims[r.Unit]})
}

func (c *Core) release(r Request) Reply {
	switch r.Outcome {
	case "", "done", "back", "failed":
	default:
		return c.usage("--outcome is done, back or failed")
	}
	w := c.workers[r.Worker]
	if w == nil {
		return c.refuse("unknown", "no worker "+r.Worker+": register it first", nil)
	}
	if err := c.revive(w); err != nil {
		return c.failed(err)
	}
	u, ok := c.held[w.ID]
	if !ok || (r.Unit != "" && r.Unit != u) {
		return c.refuse("none", "worker "+w.ID+" holds no claim"+map[bool]string{true: " on " + r.Unit, false: ""}[r.Unit != ""], nil)
	}
	e := c.releaseEvent(c.claims[u], r.Outcome)
	e.Tokens, e.Seconds, e.Ref = r.Tokens, r.Seconds, r.Ref
	e, err := c.emit(e)
	if err != nil {
		return c.failed(err)
	}
	return c.reply(Reply{"event": e})
}

func (c *Core) emitOp(r Request) Reply {
	if !kindRe.MatchString(r.Kind) {
		return c.usage("emit needs a kind of lower-case words, such as review-filed")
	}
	if ownKinds[r.Kind] {
		return c.usage("kind " + r.Kind + " belongs to an op of its own")
	}
	e, err := c.emit(Event{Kind: r.Kind, Worker: r.Worker, Unit: r.Unit, Activity: r.Activity, Tags: r.Tags,
		Outcome: r.Outcome, Tokens: r.Tokens, Seconds: r.Seconds, Ref: r.Ref, Reason: r.Reason})
	if err != nil {
		return c.failed(err)
	}
	return c.reply(Reply{"event": e})
}
