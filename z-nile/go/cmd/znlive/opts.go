package main

import (
	"flag"
	"os"
	"strings"

	"znile/internal/live"
)

// opts holds every flag of every op; an op reads the ones it uses.
type opts struct {
	dir, worker, cli, as, session, mode, can   string
	unit, activity, action, step, needs        string
	outcome, ref, reason, kind                 string
	raft, project, tributary, risk, model      string
	pid, round                                 int
	tokens, seconds, since                     int64
	timeout                                    float64
	follow                                     bool
	limit                                      limits
	lostAfter, idleExit, tickEvery, checkEvery string
	visited                                    map[string]bool
}

func (o *opts) bind(fs *flag.FlagSet) {
	for name, p := range map[string]*string{"dir": &o.dir, "worker": &o.worker, "cli": &o.cli, "as": &o.as,
		"session": &o.session, "mode": &o.mode, "can": &o.can, "unit": &o.unit, "activity": &o.activity,
		"action": &o.action, "step": &o.step, "needs": &o.needs, "outcome": &o.outcome, "ref": &o.ref,
		"reason": &o.reason, "kind": &o.kind, "raft": &o.raft, "project": &o.project, "tributary": &o.tributary,
		"risk": &o.risk, "model": &o.model, "lost-after": &o.lostAfter, "idle-exit": &o.idleExit,
		"tick-every": &o.tickEvery, "check-every": &o.checkEvery} {
		fs.StringVar(p, name, "", name)
	}
	fs.IntVar(&o.pid, "pid", 0, "pid")
	fs.IntVar(&o.round, "round", 0, "round")
	fs.Int64Var(&o.tokens, "tokens", 0, "tokens")
	fs.Int64Var(&o.seconds, "seconds", 0, "seconds")
	fs.Int64Var(&o.since, "since", 0, "events after this seq")
	fs.Float64Var(&o.timeout, "timeout", 0, "seconds")
	fs.BoolVar(&o.follow, "follow", false, "stream events")
	fs.Var(o.limit, "limit", "class=n, repeatable")
}

// request builds the wire request; the worker defaults to ZN_WORKER.
func (o *opts) request(op, kind, dir string) live.Request {
	w := o.worker
	if w == "" {
		w = os.Getenv("ZN_WORKER")
	}
	r := live.Request{Op: op, Dir: dir, Proto: live.Proto, Worker: w, CLI: o.cli, As: o.as, PID: o.pid,
		Session: o.session, Mode: o.mode, Unit: o.unit, Activity: o.activity, Action: o.action, Step: o.step,
		Needs: o.needs, Tags: live.Tags{Raft: o.raft, Project: o.project, Tributary: o.tributary, Risk: o.risk,
			Round: o.round, Model: o.model},
		Outcome: o.outcome, Tokens: o.tokens, Seconds: o.seconds, Ref: o.ref, Reason: o.reason, Kind: kind,
		Follow: o.follow, Timeout: o.timeout}
	if o.can != "" {
		r.Can = strings.Split(o.can, ",")
	}
	if len(o.limit) > 0 {
		r.Limit = o.limit
	}
	if o.visited["since"] {
		s := o.since
		r.Since = &s
	}
	if op == "events" {
		r.Kind = o.kind
	}
	return r
}
