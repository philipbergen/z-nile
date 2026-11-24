package live

import (
	"fmt"
	"regexp"
	"runtime"
	"sort"
	"strings"
)

var kindRe = regexp.MustCompile(`^[a-z][a-z0-9-]*$`)

// accountRe is a worker's account label: a short word the owner sets per terminal (f0420). It reaches HTML and shell
// words, so it is narrower than an id: letters, digits, dot, underscore and dash, at most 32, no `@`, no `/`, no `:`.
var accountRe = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$`)

// idRe is what a worker, unit, activity, cli, session or can entry may look like. These reach shell commands, TSV
// files and HTML, so nothing else passes.
var idRe = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._@:/-]{0,127}$`)

const maxText = 500

var badIDChar = regexp.MustCompile(`[^A-Za-z0-9._@:/-]`)

// idHost maps every character of a host name outside the id class to "-", so a host with a space or an apostrophe
// still yields a valid worker id.
func idHost(h string) string { return badIDChar.ReplaceAllString(h, "-") }

// MaxPID is the largest pid the platform hands out; a larger number is not a process (and 4294967295 would wrap to
// kill(-1, 0), which is alive forever).
var MaxPID = map[string]int{"darwin": 99999}[runtime.GOOS]

func init() {
	if MaxPID == 0 {
		MaxPID = 4194304
	}
}

// ownKinds are the kinds the ops themselves append; emit refuses them.
var ownKinds = map[string]bool{"registered": true, "claimed": true, "released": true, "gone": true,
	"lost": true, "revived": true, "stop": true, "poke": true}

// showsState lists the ops whose reply shows the worker the state it decides from, so its seen moves to that reply.
// Every other reply (beat, emit, poke, register, release, gone, stop) leaves seen where it was, or a wake that
// happened between the decision and the wait would be missed.
var showsState = map[string]bool{"claims": true, "workers": true, "status": true, "claim": true}

// fromOutside are the ops that act on the named worker from outside: they say nothing of its hearing and never
// revive it.
var fromOutside = map[string]bool{"gone": true, "stop": true}

// wakes reports whether an event can wake the waiter. A waiter is never woken by its own events, and a stop event
// wakes only the worker it names.
func wakes(e Event, waiter string) bool {
	switch e.Kind {
	case "registered", "claimed", "lost", "revived":
		return false
	case "stop":
		return e.Worker == waiter
	}
	return e.Worker != waiter
}

func badText(s string) string {
	if len(s) > maxText {
		return fmt.Sprintf("is over %d bytes", maxText)
	}
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			return "has a control character"
		}
	}
	return ""
}

// Validate checks every field a request carries. It returns the offending field and why, or "" when all are fine.
func Validate(r Request) (field, why string) {
	ids := []struct{ name, v string }{{"worker", r.Worker}, {"as", r.As}, {"cli", r.CLI}, {"session", r.Session},
		{"unit", r.Unit}, {"activity", r.Activity}, {"needs", r.Needs}}
	for _, f := range ids {
		if f.v != "" && !idRe.MatchString(f.v) {
			return f.name, "must match " + idRe.String()
		}
	}
	if r.Account != "" && !accountRe.MatchString(r.Account) {
		return "account", "must match " + accountRe.String()
	}
	if len(r.Can) > 64 || len(r.Limit) > 16 {
		return "can", "has too many entries"
	}
	for _, a := range r.Can {
		if !idRe.MatchString(a) {
			return "can", "entry " + fmt.Sprintf("%q", a) + " must match " + idRe.String()
		}
	}
	for class := range r.Limit {
		if !idRe.MatchString(class) {
			return "limit", "class must match " + idRe.String()
		}
	}
	texts := []struct{ name, v string }{{"reason", r.Reason}, {"ref", r.Ref}, {"action", r.Action}, {"step", r.Step},
		{"raft", r.Raft}, {"project", r.Project}, {"tributary", r.Tributary}, {"risk", r.Risk}, {"model", r.Model},
		{"mode", r.Mode}, {"outcome", r.Outcome}, {"page", r.Page}}
	for _, f := range texts {
		if w := badText(f.v); w != "" {
			return f.name, w
		}
	}
	if r.Kind != "" && !kindRe.MatchString(r.Kind) {
		return "kind", "must be lower-case words, such as review-filed"
	}
	if r.Op == "register" && r.PID != 0 && (r.PID < 2 || r.PID > MaxPID) {
		return "pid", fmt.Sprintf("must be between 2 and %d", MaxPID)
	}
	return "", ""
}

// Check returns a usage refusal for a request with a bad field, or nil.
func (c *Core) Check(r Request) Reply {
	field, why := Validate(r)
	if field == "" {
		return nil
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.usage(field + " " + why)
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

// Touch revives a lost worker, as any op naming it does.
func (c *Core) Touch(worker string) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if w := c.workers[worker]; w != nil {
		return c.revive(w)
	}
	return nil
}

// Do runs one non-blocking op. A request naming a lost worker revives it (but gone and stop, which act from
// outside); naming any known worker marks it heard; and only the ops that show state move its seen.
func (c *Core) Do(r Request) Reply {
	if rep := c.Check(r); rep != nil {
		return rep
	}
	// f0420: a beat may name the worker by its CLI and pid, the id the daemon builds, so a command that cannot know the
	// host name beats in one call
	if r.Op == "beat" && r.Worker == "" && r.CLI != "" && r.PID > 0 {
		r.Worker = fmt.Sprintf("%s-%d@%s", r.CLI, r.PID, idHost(c.cfg.Host))
	}
	var start string
	if r.Op == "register" && r.PID > 0 {
		procs, err := c.cfg.Probe.Procs([]int{r.PID}) // outside the lock: it runs ps
		c.mu.Lock()
		defer c.mu.Unlock()
		p, known := procs[r.PID]
		switch {
		case err != nil:
			return c.refuse("probe", "cannot ask ps about pid "+fmt.Sprint(r.PID)+": "+err.Error(), nil)
		case !known:
			return c.usage(fmt.Sprintf("pid: no process has pid %d", r.PID))
		case p.Zombie:
			return c.usage(fmt.Sprintf("pid: process %d has ended", r.PID))
		}
		start = p.Start
	} else {
		c.mu.Lock()
		defer c.mu.Unlock()
	}
	if w := c.workers[r.Worker]; w != nil && r.Op != "register" && !fromOutside[r.Op] {
		if err := c.revive(w); err != nil {
			return c.failed(err)
		}
	}
	out := c.do(r, start)
	if w := c.workers[r.Worker]; w != nil && !fromOutside[r.Op] {
		c.hear(w)
		if showsState[r.Op] && c.seq > w.Seen {
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
		cs := []Claim{}
		for _, cl := range c.sortedClaims() {
			cs = append(cs, *cl)
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
		id = fmt.Sprintf("%s-%d@%s", r.CLI, r.PID, idHost(c.cfg.Host))
		if r.As != "" {
			id += "." + r.As
		}
	}
	if !idRe.MatchString(id) {
		return c.usage("worker " + id + " must match " + idRe.String())
	}
	mode := r.Mode
	if mode == "" {
		mode = "plain"
	}
	// f0421: a session's model is fixed when it registers, judged against the worker of the same process (CLI, pid, start)
	// before a session change can replace that worker. The model arrives as `<id>` or `<id> (declared)`; the mark is kept
	// apart, so both spellings of one id are one model, and once a process's model is marked declared it stays marked. The
	// same process naming no model (an engine from before f0421 S1a, or one that could not read the table) keeps the
	// recorded model; only another model is refused, whatever the session id. A check of the variable, not a lock.
	model, declared := splitModel(r.Model)
	if prev := c.workers[id]; prev != nil && prev.CLI == r.CLI && prev.PID == r.PID && sameStart(prev.Start, start) &&
		prev.Model != "" {
		if model != "" && model != prev.Model {
			return c.refuse("model", "worker "+id+" registered running "+prev.Model+" and is asked to run "+model+
				": a session's model is fixed when it registers; ask the person to start a new terminal with ZN_MODEL set to "+
				model, nil)
		}
		model, declared = prev.Model, declared || prev.Declared
	}
	if old := c.workers[id]; old != nil && old.Session != r.Session {
		if err := c.remove(old, "lost"); err != nil {
			return c.failed(err)
		}
	}
	old := c.workers[id]
	if old != nil {
		if err := c.revive(old); err != nil {
			return c.failed(err)
		}
	}
	if old != nil && old.CLI == r.CLI && old.PID == r.PID && sameStart(old.Start, start) && old.Mode == mode &&
		old.Account == r.Account && old.Model == model && old.Declared == declared &&
		strings.Join(old.Can, ",") == strings.Join(r.Can, ",") {
		return c.reply(Reply{"worker": id})
	}
	if _, err := c.emit(Event{Kind: "registered", Worker: id, CLI: r.CLI, PID: r.PID, Start: start,
		Session: r.Session, Mode: mode, Can: r.Can, Account: r.Account, Tags: Tags{Model: model}, Declared: declared}); err != nil {
		return c.failed(err)
	}
	return c.reply(Reply{"worker": id})
}

// declaredMark ends a model a session only declared (f0421): the engine sends `<id> (declared)`.
const declaredMark = " (declared)"

// splitModel is a registration's model without its mark, and whether it carried the mark.
func splitModel(m string) (string, bool) {
	if strings.HasSuffix(m, declaredMark) {
		return strings.TrimSuffix(m, declaredMark), true
	}
	return m, false
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
	if r.Needs != "" && !has(w.Can, r.Needs) {
		return c.refuse("cannot", "worker "+w.ID+" cannot deliver "+r.Needs, Reply{"can": w.Can})
	}
	if u, ok := c.held[w.ID]; ok {
		cl := c.claims[u]
		if u == r.Unit && cl.Activity == r.Activity {
			return c.reply(Reply{"claim": *cl, "again": true})
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
	return c.reply(Reply{"claim": *c.claims[r.Unit]})
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
	u, ok := c.held[w.ID]
	if !ok || (r.Unit != "" && r.Unit != u) {
		return c.refuse("none", "worker "+w.ID+" holds no claim"+map[bool]string{true: " on " + r.Unit, false: ""}[r.Unit != ""], nil)
	}
	outcome := r.Outcome
	if outcome == "" {
		outcome = "done"
	}
	e := c.releaseEvent(c.claims[u], outcome)
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
		Outcome: r.Outcome, Tokens: r.Tokens, Seconds: r.Seconds, Wall: r.Wall, Ref: r.Ref, Reason: r.Reason})
	if err != nil {
		return c.failed(err)
	}
	return c.reply(Reply{"event": e})
}
