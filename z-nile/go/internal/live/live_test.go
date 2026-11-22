package live_test

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"znile/internal/live"
)

// clock keeps a wall clock and a monotonic one apart, so a test can jump the first without moving the second.
type clock struct {
	mu   sync.Mutex
	t    time.Time
	mono time.Duration
}

func (c *clock) Now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *clock) Mono() time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.mono
}

// Add moves both clocks.
func (c *clock) Add(d time.Duration) {
	c.mu.Lock()
	c.t = c.t.Add(d)
	c.mono += d
	c.mu.Unlock()
}

// Jump moves the wall clock alone, as a clock correction does.
func (c *clock) Jump(d time.Duration) {
	c.mu.Lock()
	c.t = c.t.Add(d)
	c.mu.Unlock()
}

// probe is a table of pids: alive or not, each one's start time, zombies, and whether ps fails.
type probe struct {
	mu     sync.Mutex
	dead   map[int]bool
	start  map[int]string
	zombie map[int]bool
	fail   error
}

func newProbe() *probe {
	return &probe{dead: map[int]bool{}, start: map[int]string{}, zombie: map[int]bool{}}
}
func (p *probe) Alive(pid int) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return !p.dead[pid]
}
func (p *probe) Procs(pids []int) (map[int]live.Proc, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.fail != nil {
		return nil, p.fail
	}
	out := map[int]live.Proc{}
	for _, pid := range pids {
		if s, ok := p.start[pid]; ok {
			out[pid] = live.Proc{Start: s, Zombie: p.zombie[pid]}
		}
	}
	return out, nil
}
func (p *probe) set(pid int, dead bool, start string) {
	p.mu.Lock()
	p.dead[pid], p.start[pid] = dead, start
	p.mu.Unlock()
}

type mem struct {
	mu sync.Mutex
	ev []live.Event
}

func (m *mem) Append(e live.Event) error {
	m.mu.Lock()
	m.ev = append(m.ev, e)
	m.mu.Unlock()
	return nil
}
func (m *mem) kinds() []string {
	m.mu.Lock()
	defer m.mu.Unlock()
	var k []string
	for _, e := range m.ev {
		k = append(k, e.Kind+"/"+e.Outcome)
	}
	return k
}

type rig struct {
	c  *live.Core
	ck *clock
	pr *probe
	m  *mem
}

func newRig(lostAfter time.Duration) *rig {
	r := &rig{ck: &clock{t: time.Unix(1_700_000_000, 0)}, pr: newProbe(), m: &mem{}}
	r.c = live.New(live.Config{Host: "h", Now: r.ck.Now, Mono: r.ck.Mono, Sink: r.m, Probe: r.pr, LostAfter: lostAfter,
		TickEvery: 2 * time.Second})
	return r
}

func (r *rig) reg(t *testing.T, id string, pid int, session string, can ...string) {
	t.Helper()
	if _, ok := r.pr.start[pid]; !ok {
		r.pr.set(pid, false, "start-"+fmt.Sprint(pid))
	}
	rep := r.c.Do(live.Request{Op: "register", Worker: id, CLI: "t", PID: pid, Session: session, Can: can})
	if !rep.OK() {
		t.Fatalf("register %s: %v", id, rep)
	}
}

func (r *rig) claim(w, unit, act string) live.Reply {
	return r.c.Do(live.Request{Op: "claim", Worker: w, Unit: unit, Activity: act})
}

// AC1: of 50 goroutine clients claiming one unit at once, in each of 200 rounds exactly one wins.
func TestRaceOneWinnerEachRound(t *testing.T) {
	r := newRig(time.Hour)
	const n, rounds = 50, 200
	for i := 0; i < n; i++ {
		r.reg(t, fmt.Sprint("w", i), 1000+i, "")
	}
	for round := 0; round < rounds; round++ {
		gate := make(chan struct{})
		replies := make([]live.Reply, n)
		var wg sync.WaitGroup
		for i := 0; i < n; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				<-gate
				replies[i] = r.claim(fmt.Sprint("w", i), "R0099", "design")
			}()
		}
		close(gate)
		wg.Wait()
		winner, wins := "", 0
		for i, rep := range replies {
			if rep.OK() {
				wins++
				winner = fmt.Sprint("w", i)
			}
		}
		if wins != 1 {
			t.Fatalf("round %d: %d winners", round, wins)
		}
		for i, rep := range replies {
			if !rep.OK() && (rep.Refused() != "held" || rep["holder"] != winner) {
				t.Fatalf("round %d: w%d got %v, want held by %s", round, i, rep, winner)
			}
		}
		if rep := r.c.Do(live.Request{Op: "release", Worker: winner, Outcome: "done"}); !rep.OK() {
			t.Fatal(rep)
		}
	}
}

// AC2: one claim per unit, one per worker, the cap, and the holder's repeat.
func TestClaimRules(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "a", 101, "", "design/1")
	r.reg(t, "b", 102, "")
	r.reg(t, "c", 103, "")
	if rep := r.claim("a", "u1", "design"); !rep.OK() {
		t.Fatal(rep)
	}
	rep := r.claim("b", "u1", "review") // another activity on a held unit
	if rep.Refused() != "held" || rep["holder"] != "a" || rep["activity"] != "design" {
		t.Fatalf("second activity: %v", rep)
	}
	if rep := r.claim("a", "u2", "design"); rep.Refused() != "busy" {
		t.Fatalf("a holds a claim: %v", rep)
	}
	if rep := r.claim("a", "u1", "design"); !rep.OK() || rep["again"] != true {
		t.Fatalf("repeat: %v", rep)
	}
	if rep := r.c.Do(live.Request{Op: "claim", Worker: "b", Unit: "u3", Activity: "x", Needs: "design/1"}); rep.Refused() != "cannot" {
		t.Fatalf("needs: %v", rep)
	}
	// the cap: three held claims carry class gate, the fourth is refused
	for i := 0; i < 3; i++ {
		id := fmt.Sprint("g", i)
		r.reg(t, id, 10+i, "")
		rep := r.c.Do(live.Request{Op: "claim", Worker: id, Unit: fmt.Sprint("gu", i), Activity: "fix", Limit: map[string]int{"gate": 3}})
		if !rep.OK() {
			t.Fatalf("claim %d under the cap: %v", i, rep)
		}
	}
	rep = r.c.Do(live.Request{Op: "claim", Worker: "c", Unit: "gu9", Activity: "fix", Limit: map[string]int{"gate": 3}})
	if rep.Refused() != "cap" {
		t.Fatalf("over the cap: %v", rep)
	}
	if rep := r.c.Do(live.Request{Op: "release", Worker: "c"}); rep.Refused() != "none" {
		t.Fatalf("release nothing: %v", rep)
	}
	if rep := r.c.Do(live.Request{Op: "nope"}); rep.Refused() != "usage" {
		t.Fatalf("unknown op: %v", rep)
	}
}

// AC3: register again keeps the claim and appends nothing; another session ends the old one first.
func TestRegisterIdempotent(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "w", 105, "s1", "design/1")
	if rep := r.claim("w", "u", "design"); !rep.OK() {
		t.Fatal(rep)
	}
	before := len(r.m.kinds())
	r.reg(t, "w", 105, "s1", "design/1")
	if n := len(r.m.kinds()); n != before {
		t.Fatalf("a repeat appended %d events: %v", n-before, r.m.kinds())
	}
	if rep := r.c.Do(live.Request{Op: "claims"}); len(rep["claims"].([]live.Claim)) != 1 {
		t.Fatalf("claim lost: %v", rep)
	}
	r.reg(t, "w", 105, "s2", "design/1")
	got := r.m.kinds()[before:]
	want := []string{"released/lost", "gone/", "registered/"}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("another session: %v, want %v", got, want)
	}
	if rep := r.c.Do(live.Request{Op: "claims"}); len(rep["claims"].([]live.Claim)) != 0 {
		t.Fatalf("old claim kept: %v", rep)
	}
}

// AC4: a pid that ended, or was reused with another start time, is released (lost) and removed.
func TestDeadAndReusedPid(t *testing.T) {
	r := newRig(time.Hour)
	r.pr.set(107, false, "1700000000.0")
	r.pr.set(108, false, "1700000000.0")
	r.reg(t, "dead", 107, "")
	r.reg(t, "reused", 108, "")
	r.claim("dead", "u1", "design")
	r.claim("reused", "u2", "design")
	if err := r.c.Tick(true); err != nil {
		t.Fatal(err)
	}
	if w, c := r.c.Counts(); w != 2 || c != 2 {
		t.Fatalf("both alive: %d workers %d claims", w, c)
	}
	r.pr.set(107, true, "")
	r.pr.set(108, false, "1700005400.0")
	if err := r.c.Tick(false); err != nil { // a signal check alone sees the dead one only
		t.Fatal(err)
	}
	if w, _ := r.c.Counts(); w != 1 {
		t.Fatalf("after the signal check: %d workers", w)
	}
	if err := r.c.Tick(true); err != nil {
		t.Fatal(err)
	}
	if w, c := r.c.Counts(); w != 0 || c != 0 {
		t.Fatalf("after the start check: %d workers %d claims", w, c)
	}
	got := r.m.kinds()[len(r.m.kinds())-4:]
	want := []string{"released/lost", "gone/", "released/lost", "gone/"}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("events %v, want %v", got, want)
	}
	if rep := r.claim("dead", "u1", "design"); rep.Refused() != "unknown" {
		t.Fatalf("removed worker: %v", rep)
	}
}

// AC5: a silent worker with a live pid becomes lost and keeps its claim; a beat revives it.
func TestLostKeepsClaim(t *testing.T) {
	r := newRig(100 * time.Second)
	r.reg(t, "w", 109, "")
	r.claim("w", "u", "design")
	r.ck.Add(99 * time.Second)
	r.c.Tick(false)
	state := func() string {
		return r.c.Do(live.Request{Op: "workers"})["workers"].([]*live.Worker)[0].State
	}
	if s := state(); s != "working" {
		t.Fatalf("before lost-after: %s", s)
	}
	r.ck.Add(2 * time.Second)
	r.c.Tick(false)
	if s := state(); s != "lost" {
		t.Fatalf("after lost-after: %s", s)
	}
	if rep := r.claim("other", "u", "design"); rep.Refused() == "" {
		t.Fatal("a lost worker's unit was taken")
	}
	if _, c := r.c.Counts(); c != 1 {
		t.Fatal("claim released")
	}
	if rep := r.c.Do(live.Request{Op: "beat", Worker: "w"}); !rep.OK() || rep["state"] != "working" {
		t.Fatalf("beat: %v", rep)
	}
	k := r.m.kinds()
	if k[len(k)-1] != "revived/" || k[len(k)-2] != "lost/" {
		t.Fatalf("events %v", k)
	}
}

func wait(r *rig, w string, since *int64, d time.Duration) live.Reply {
	ctx, cancel := context.WithTimeout(context.Background(), d)
	defer cancel()
	return r.c.Wait(ctx, w, since)
}

// AC6: wait starts at the worker's seen, so an event from before the wait connected wakes it, and the waiter's own
// events never do.
func TestWaitStartsAtSeen(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "a", 101, "")
	r.reg(t, "b", 102, "")
	r.claim("a", "u", "design")
	r.c.Do(live.Request{Op: "claims", Worker: "a"}) // a decides to wait: this reply sets its seen
	if rep := wait(r, "a", nil, 50*time.Millisecond); rep.Refused() != "timeout" {
		t.Fatalf("own events woke a: %v", rep)
	}
	r.c.Do(live.Request{Op: "release", Worker: "a", Outcome: "done"})
	r.c.Do(live.Request{Op: "claims", Worker: "a"})
	r.claim("b", "u", "review") // after a's last reply, before its wait connects
	r.c.Do(live.Request{Op: "release", Worker: "b", Outcome: "done"})
	rep := wait(r, "a", nil, time.Second)
	if !rep.OK() || rep["event"].(live.Event).Kind != "released" || rep["event"].(live.Event).Worker != "b" {
		t.Fatalf("missed the wake: %v", rep)
	}
	// a stop wakes only the worker it names
	r.c.Do(live.Request{Op: "stop", Worker: "b"})
	if rep := wait(r, "a", nil, 50*time.Millisecond); !rep.OK() && rep.Refused() != "timeout" {
		t.Fatal(rep)
	}
	if rep := wait(r, "b", nil, time.Second); !rep.OK() || rep["event"].(live.Event).Kind != "stop" {
		t.Fatalf("stop did not wake b: %v", rep)
	}
}

// A blocked wait wakes on a release made later, and a hang-up ends it.
func TestWaitBlocksThenWakes(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "a", 101, "")
	r.reg(t, "b", 102, "")
	r.claim("b", "u", "design")
	r.c.Do(live.Request{Op: "claims", Worker: "a"})
	got := make(chan live.Reply, 1)
	go func() { got <- wait(r, "a", nil, 5*time.Second) }()
	time.Sleep(50 * time.Millisecond)
	r.c.Do(live.Request{Op: "release", Worker: "b"})
	select {
	case rep := <-got:
		if !rep.OK() {
			t.Fatal(rep)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("not woken")
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan live.Reply, 1)
	go func() { done <- r.c.Wait(ctx, "a", nil) }()
	cancel()
	if rep := <-done; rep.Refused() != "closed" {
		t.Fatalf("hang-up: %v", rep)
	}
}

// F1: seen moves only on replies that show state. A beat, an emit or a poke between the decision (claims) and the
// wait must not swallow the release that happened in the gap.
func TestWaitNotSwallowedByLaterOps(t *testing.T) {
	gaps := map[string]live.Request{
		"beat":     {Op: "beat", Worker: "a"},
		"emit":     {Op: "emit", Kind: "design-filed", Worker: "a"},
		"poke":     {Op: "poke", Worker: "a", Reason: "x"},
		"register": {Op: "register", Worker: "a", CLI: "t", PID: 101, Session: "s"},
	}
	for name, gap := range gaps {
		r := newRig(time.Hour)
		r.reg(t, "a", 101, "s")
		r.reg(t, "b", 102, "")
		r.claim("b", "u", "design")
		r.c.Do(live.Request{Op: "claims", Worker: "a"}) // a decides: u is held
		r.c.Do(live.Request{Op: "release", Worker: "b", Outcome: "done"})
		if rep := r.c.Do(gap); !rep.OK() {
			t.Fatalf("%s: %v", name, rep)
		}
		rep := wait(r, "a", nil, 500*time.Millisecond)
		if !rep.OK() || rep["event"].(live.Event).Kind != "released" {
			t.Fatalf("%s in the gap swallowed the release: %v", name, rep)
		}
	}
}

// F1: a claim reply, a workers reply and a status reply do show state.
func TestSeenMovesOnStateReplies(t *testing.T) {
	for _, op := range []string{"claims", "workers", "status"} {
		r := newRig(time.Hour)
		r.reg(t, "a", 101, "")
		r.reg(t, "b", 102, "")
		r.claim("b", "u", "design")
		r.c.Do(live.Request{Op: "release", Worker: "b"})
		r.c.Do(live.Request{Op: op, Worker: "a"})
		if rep := wait(r, "a", nil, 50*time.Millisecond); rep.Refused() != "timeout" {
			t.Fatalf("%s did not move seen: %v", op, rep)
		}
	}
}

// F9 (AC6): the waiter's own events of a waking kind (an emit, a release) do not wake it.
func TestOwnWakingEventsDoNotWake(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "a", 101, "")
	r.claim("a", "u", "design")
	r.c.Do(live.Request{Op: "claims", Worker: "a"})
	r.c.Do(live.Request{Op: "emit", Kind: "review-filed", Worker: "a"})
	r.c.Do(live.Request{Op: "release", Worker: "a"})
	if rep := wait(r, "a", nil, 50*time.Millisecond); rep.Refused() != "timeout" {
		t.Fatalf("its own events woke it: %v", rep)
	}
}

// F9 (AC3): a repeat register with a changed field keeps the claim and appends one registered event.
func TestRegisterChangedFieldKeepsClaim(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "w", 101, "s1", "design/1")
	r.claim("w", "u", "design")
	before := len(r.m.kinds())
	r.reg(t, "w", 101, "s1", "design/1", "review/2")
	if got := r.m.kinds()[before:]; fmt.Sprint(got) != "[registered/]" {
		t.Fatalf("events %v", got)
	}
	if _, c := r.c.Counts(); c != 1 {
		t.Fatal("claim dropped")
	}
	if w := r.c.Do(live.Request{Op: "workers"})["workers"].([]*live.Worker)[0]; len(w.Can) != 2 || w.State != "working" {
		t.Fatalf("worker %+v", w)
	}
}

// F2 (core side): a register with --as and no worker builds <cli>-<pid>@<host>.<as>, beside the parent.
func TestRegisterAsBuildsID(t *testing.T) {
	r := newRig(time.Hour)
	r.pr.set(101, false, "s")
	rep := r.c.Do(live.Request{Op: "register", CLI: "claude", PID: 101})
	if rep["worker"] != "claude-101@h" {
		t.Fatal(rep)
	}
	r.claim("claude-101@h", "u", "design")
	rep = r.c.Do(live.Request{Op: "register", CLI: "claude", PID: 101, As: "sub1"})
	if rep["worker"] != "claude-101@h.sub1" {
		t.Fatal(rep)
	}
	if _, c := r.c.Counts(); c != 1 {
		t.Fatal("the parent lost its claim")
	}
}

// f0420: a worker's account label is a short, safe word the owner sets per terminal. It is part of the record, a change
// of it re-registers and keeps the claim, and a label that is not a short safe word is refused before anything is stored.
func TestRegisterAccountLabel(t *testing.T) {
	r := newRig(time.Hour)
	r.pr.set(101, false, "s")
	rep := r.c.Do(live.Request{Op: "register", CLI: "claude", PID: 101, Account: "work.2-a_b"})
	if !rep.OK() {
		t.Fatal(rep)
	}
	r.claim("claude-101@h", "u", "design")
	before := len(r.m.kinds())
	r.c.Do(live.Request{Op: "register", CLI: "claude", PID: 101, Account: "work.2-a_b"})
	if n := len(r.m.kinds()); n != before {
		t.Fatalf("a repeat appended %v", r.m.kinds()[before:])
	}
	r.c.Do(live.Request{Op: "register", CLI: "claude", PID: 101, Account: "home"})
	if got := r.m.kinds()[before:]; fmt.Sprint(got) != "[registered/]" {
		t.Fatalf("a changed label appended %v", got)
	}
	w := r.c.Do(live.Request{Op: "workers"})["workers"].([]*live.Worker)[0]
	if w.Account != "home" || w.State != "working" {
		t.Fatalf("worker %+v", w)
	}
	for _, bad := range []string{"a b", "-x", "a;b", "<b>", "$(x)", "a\nb", strings.Repeat("x", 33), "x@y.com"} {
		rep := r.c.Do(live.Request{Op: "register", CLI: "claude", PID: 101, Account: bad})
		if rep.Refused() != "usage" || !strings.Contains(rep["why"].(string), "account") {
			t.Fatalf("%q: %v", bad, rep)
		}
	}
}

// F5: ids and free text are validated, and the ids the design builds pass.
func TestValidation(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "claude-123@host.local.as", 101, "", "code-review/normal")
	long := strings.Repeat("x", 129)
	bad := map[string]live.Request{
		"worker":   {Op: "beat", Worker: "a\nb"},
		"unit":     {Op: "claim", Worker: "w", Unit: "../../x", Activity: "a"},
		"activity": {Op: "claim", Worker: "w", Unit: "u", Activity: "<script>"},
		"cli":      {Op: "register", CLI: "a b", PID: 101},
		"session":  {Op: "register", CLI: "c", PID: 101, Session: "s\x00"},
		"can":      {Op: "register", CLI: "c", PID: 101, Can: []string{"a/b", "x y/1"}},
		"as":       {Op: "register", CLI: "c", PID: 101, As: "a;b"},
		"needs":    {Op: "claim", Worker: "w", Unit: "u", Activity: "a", Needs: "$(x)/1"},
		"reason":   {Op: "poke", Reason: "a\nb"},
		"ref":      {Op: "poke", Ref: strings.Repeat("a", 501)},
		"model":    {Op: "emit", Kind: "x", Tags: live.Tags{Model: "m\x00"}},
		"worker2":  {Op: "beat", Worker: long},
	}
	for field, req := range bad {
		rep := r.c.Do(req)
		if rep.Refused() != "usage" || !strings.Contains(rep["why"].(string), strings.TrimSuffix(field, "2")) {
			t.Fatalf("%s: %v", field, rep)
		}
	}
	if rep := r.c.Do(live.Request{Op: "poke", Reason: "a free sentence, with punctuation: fine."}); !rep.OK() {
		t.Fatal(rep)
	}
}

// F7: a waiter whose own worker is removed is told at once.
func TestWaiterToldWhenItsWorkerIsGone(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "a", 101, "s1")
	got := make(chan live.Reply, 1)
	go func() { got <- wait(r, "a", nil, 5*time.Second) }()
	time.Sleep(50 * time.Millisecond)
	r.reg(t, "a", 101, "s2") // another session under the same id ends the old one
	select {
	case rep := <-got:
		if rep.Refused() != "gone" {
			t.Fatalf("%v", rep)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("the waiter kept waiting")
	}
	r.reg(t, "b", 102, "")
	go func() { got <- wait(r, "b", nil, 5*time.Second) }()
	time.Sleep(50 * time.Millisecond)
	r.c.Do(live.Request{Op: "gone", Worker: "b"})
	if rep := <-got; rep.Refused() != "gone" {
		t.Fatalf("%v", rep)
	}
}

// F11: any op naming a lost worker, except gone and stop, revives it.
func TestAnyOpRevivesLostWorker(t *testing.T) {
	ops := []live.Request{{Op: "beat"}, {Op: "claims"}, {Op: "workers"}, {Op: "status"}, {Op: "poke"},
		{Op: "emit", Kind: "x"}, {Op: "claim", Unit: "u", Activity: "a"},
		{Op: "register", CLI: "t", PID: 101, Session: "s", Can: []string{"x/1"}}}
	for _, op := range ops {
		r := newRig(10 * time.Second)
		r.reg(t, "w", 101, "s")
		r.ck.Add(11 * time.Second)
		r.c.Tick(false)
		state := func() string { return r.c.Do(live.Request{Op: "workers"})["workers"].([]*live.Worker)[0].State }
		// the read above revives too, so look at the events instead
		op.Worker = "w"
		if rep := r.c.Do(op); !rep.OK() {
			t.Fatalf("%s: %v", op.Op, rep)
		}
		k := r.m.kinds()
		if !strings.Contains(fmt.Sprint(k), "lost/") || !strings.Contains(fmt.Sprint(k), "revived/") {
			t.Fatalf("%s left the worker lost: %v", op.Op, k)
		}
		if s := state(); s == "lost" {
			t.Fatalf("%s: still lost", op.Op)
		}
	}
	r := newRig(10 * time.Second)
	r.reg(t, "w", 101, "s")
	r.ck.Add(11 * time.Second)
	r.c.Tick(false)
	r.c.Do(live.Request{Op: "stop", Worker: "w"})
	if k := fmt.Sprint(r.m.kinds()); strings.Contains(k, "revived") {
		t.Fatalf("stop revived: %s", k)
	}
}

// F14: pids that are not processes are refused, a zombie is dead, and a failing or ignorant ps is an error.
func TestPidRules(t *testing.T) {
	r := newRig(time.Hour)
	for _, pid := range []int{1, 99999 + 1, 4294967295} {
		rep := r.c.Do(live.Request{Op: "register", Worker: "w", CLI: "t", PID: pid})
		if rep.Refused() != "usage" || !strings.Contains(rep["why"].(string), "pid") {
			t.Fatalf("pid %d: %v", pid, rep)
		}
	}
	// ps does not know the pid: refused, never stored with an empty start time (that would switch the reuse check off)
	if rep := r.c.Do(live.Request{Op: "register", Worker: "w", CLI: "t", PID: 5000}); rep.Refused() != "usage" {
		t.Fatalf("unknown pid: %v", rep)
	}
	r.pr.fail = errors.New("ps: boom")
	r.pr.set(5001, false, "x")
	if rep := r.c.Do(live.Request{Op: "register", Worker: "w", CLI: "t", PID: 5001}); rep.Refused() != "probe" {
		t.Fatalf("ps failure: %v", rep)
	}
	r.pr.fail = nil
	r.reg(t, "z", 5001, "")
	r.claim("z", "u", "design")
	r.pr.zombie[5001] = true
	r.c.Tick(false) // the signal check still sees it
	if w, _ := r.c.Counts(); w != 1 {
		t.Fatal("zombie removed by the signal check alone")
	}
	r.c.Tick(true)
	if w, c := r.c.Counts(); w != 0 || c != 0 {
		t.Fatalf("zombie kept: %d %d", w, c)
	}
	if rep := r.c.Do(live.Request{Op: "register", Worker: "w", CLI: "t", PID: 5001}); rep.Refused() != "usage" {
		t.Fatalf("zombie registered: %v", rep)
	}
}

// F15: a wall-clock jump marks nobody lost; after a sleep (a late tick) every worker gets a fresh interval.
func TestClockJumpAndSleep(t *testing.T) {
	r := newRig(100 * time.Second)
	r.reg(t, "w", 101, "")
	r.claim("w", "u", "design")
	r.c.Tick(false)
	r.ck.Jump(10 * time.Hour)
	r.c.Tick(false)
	if k := fmt.Sprint(r.m.kinds()); strings.Contains(k, "lost") {
		t.Fatalf("a clock jump made a worker lost: %s", k)
	}
	r.ck.Add(1000 * time.Second) // the machine slept: the next tick is late
	r.c.Tick(false)
	if k := fmt.Sprint(r.m.kinds()); strings.Contains(k, "lost") {
		t.Fatalf("a sleep made a worker lost: %s", k)
	}
	for i := 0; i < 49; i++ { // 98 s of ordinary ticks: still fine
		r.ck.Add(2 * time.Second)
		r.c.Tick(false)
	}
	if k := fmt.Sprint(r.m.kinds()); strings.Contains(k, "lost") {
		t.Fatalf("lost before a whole interval: %s", k)
	}
	for i := 0; i < 3; i++ {
		r.ck.Add(2 * time.Second)
		r.c.Tick(false)
	}
	if k := fmt.Sprint(r.m.kinds()); !strings.Contains(k, "lost") {
		t.Fatalf("never lost: %s", k)
	}
}

// F16: a release with no outcome records done.
func TestReleaseDefaultsToDone(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "w", 101, "")
	r.claim("w", "u", "design")
	rep := r.c.Do(live.Request{Op: "release", Worker: "w"})
	if rep["event"].(live.Event).Outcome != "done" {
		t.Fatalf("%v", rep)
	}
}

type failSink struct{}

func (failSink) Append(live.Event) error {
	return errors.New("event log /x/events.jsonl: no space left")
}

// F6 (core side): a storage failure is refused with its own word and changes nothing.
func TestStorageFailureRefused(t *testing.T) {
	c := live.New(live.Config{Host: "h", Sink: failSink{}})
	rep := c.Do(live.Request{Op: "register", Worker: "w", CLI: "t", PID: 101})
	if rep.Refused() != "storage" || !strings.Contains(rep["why"].(string), "/x/events.jsonl") {
		t.Fatalf("%v", rep)
	}
	if w, _ := c.Counts(); w != 0 {
		t.Fatal("state changed")
	}
}

// N1: a removal from the worker's previous registration does not refuse a wait whose --since predates it.
func TestWaitSinceBeforeReregistrationNotGone(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "c", 101, "s1")
	old := r.c.Seq()
	r.reg(t, "c", 101, "s2") // released/gone/registered: the old registration ended
	if rep := wait(r, "c", &old, 100*time.Millisecond); rep.Refused() != "timeout" {
		t.Fatalf("%v", rep)
	}
	r.reg(t, "b", 102, "")
	r.c.Do(live.Request{Op: "poke"})
	if rep := wait(r, "c", &old, time.Second); !rep.OK() || rep["event"].(live.Event).Kind != "poke" {
		t.Fatalf("a real event did not wake it: %v", rep)
	}
	// and the end of the current registration still tells the waiter
	got := make(chan live.Reply, 1)
	go func() { got <- wait(r, "c", &old, 5*time.Second) }()
	time.Sleep(50 * time.Millisecond)
	r.reg(t, "c", 101, "s3")
	if rep := <-got; rep.Refused() != "gone" && !rep.OK() {
		t.Fatalf("%v", rep)
	}
}

// N3: an underscore is fine in ids, and a host name outside the id class still builds a valid worker id.
func TestUnderscoreAndOddHostNames(t *testing.T) {
	r := newRig(time.Hour)
	r.reg(t, "my_worker@box_1", 101, "")
	if rep := r.claim("my_worker@box_1", "unit_1", "code_review"); !rep.OK() {
		t.Fatalf("%v", rep)
	}
	for host, want := range map[string]string{"box_1": "claude-102@box_1", "my host's box": "claude-102@my-host-s-box", "é.local": "claude-102@-.local"} {
		c := live.New(live.Config{Host: host, Probe: r.pr})
		r.pr.set(102, false, "x")
		rep := c.Do(live.Request{Op: "register", CLI: "claude", PID: 102})
		if !rep.OK() || rep["worker"] != want {
			t.Fatalf("host %q: %v, want %s", host, rep, want)
		}
	}
}

// restored builds a core from step 1's log: one worker whose recorded start is text, holding one unit.
func restored(t *testing.T, recorded string, current string) *rig {
	t.Helper()
	r := newRig(time.Hour)
	r.pr.set(101, false, current)
	r.c.Restore(nil, []live.Event{
		{Seq: 1, At: 1_700_000_000, Kind: "registered", Worker: "w", CLI: "t", PID: 101, Start: recorded},
		{Seq: 2, At: 1_700_000_001, Kind: "claimed", Worker: "w", Unit: "u", Activity: "design"},
	})
	return r
}

func counts(r *rig) (int, int) {
	w, c := r.c.Counts()
	return w, c
}

// F2: a start recorded in ps's lstart spelling (step 1's logs) and a live pid with the same start in the kernel's keeps
// the worker and its claim; a genuinely different start frees the claim; an unreadable record is refreshed.
func TestStartSpellingsCompareAsTimes(t *testing.T) {
	at := time.Unix(1_700_000_000, 0).In(time.Local)
	lstart := at.Format("Mon Jan _2 15:04:05 2006")
	r := restored(t, lstart, "1700000000.250000")
	r.c.Tick(true)
	if w, c := counts(r); w != 1 || c != 1 {
		t.Fatalf("an lstart start of the same moment dropped the worker: %d workers %d claims", w, c)
	}
	r = restored(t, lstart, "1700000100.000000")
	r.c.Tick(true)
	if w, c := counts(r); w != 0 || c != 0 {
		t.Fatalf("a different start kept the claim: %d workers %d claims", w, c)
	}
	r = restored(t, "garbage", "1700000000.000000")
	r.c.Tick(true)
	if w, c := counts(r); w != 1 || c != 1 {
		t.Fatalf("an unreadable start was counted as reuse: %d %d", w, c)
	}
	r.pr.set(101, false, "1700000999.000000") // refreshed from the live process: now a real change is caught
	r.c.Tick(true)
	if w, _ := counts(r); w != 0 {
		t.Fatal("the refreshed start did not catch a reused pid")
	}
}

// F11: a lost worker with no claim is removed after 24 hours (a gone event with a reason), so the daemon can idle out; a lost
// worker with a claim is kept.
func TestLostWorkerWithoutClaimIsRemovedAfterADay(t *testing.T) {
	r := newRig(100 * time.Second)
	r.reg(t, "idle", 101, "")
	r.reg(t, "busy", 102, "")
	r.claim("busy", "u", "design")
	for i := 0; i < 80; i++ { // 160 s of ticks: both go lost
		r.ck.Add(2 * time.Second)
		r.c.Tick(false)
	}
	if w, _ := counts(r); w != 2 {
		t.Fatalf("%d workers after going lost, want 2", w)
	}
	for i := 0; i < 400; i++ { // 23 hours later, in 200 s steps (no step is read as a sleep)
		r.ck.Add(200 * time.Second)
		r.c.Tick(false)
	}
	// still under a day since it went lost: both stay
	if w, _ := counts(r); w != 2 {
		t.Fatalf("a worker was removed before a day: %d left", w)
	}
	for i := 0; i < 40; i++ {
		r.ck.Add(200 * time.Second)
		r.c.Tick(false)
	}
	w, c := counts(r)
	if w != 1 || c != 1 {
		t.Fatalf("after a day: %d workers %d claims, want the busy one only", w, c)
	}
	var gone *live.Event
	r.m.mu.Lock()
	for i := range r.m.ev {
		if r.m.ev[i].Kind == "gone" {
			gone = &r.m.ev[i]
		}
	}
	r.m.mu.Unlock()
	if gone == nil || gone.Worker != "idle" || gone.Reason == "" {
		t.Fatalf("no gone event with a reason for the idle worker: %+v", gone)
	}
}

// F11: the 24 hours of a lost worker with no claim count from when it was lost, across daemon restarts: from the log's
// `lost` event, or from the snapshot's lost_since.
func TestLostDayCountsAcrossRestarts(t *testing.T) {
	for _, viaSnapshot := range []bool{false, true} {
		r := newRig(100 * time.Second)
		r.reg(t, "idle", 101, "")
		for i := 0; i < 80; i++ {
			r.ck.Add(2 * time.Second)
			r.c.Tick(false)
		}
		if k := fmt.Sprint(r.m.kinds()); !strings.Contains(k, "lost") {
			t.Fatalf("never lost: %s", k)
		}
		restart := func(after time.Duration, prior *rig) *rig {
			n := newRig(100 * time.Second)
			n.pr.set(101, false, "start-101")
			n.ck.Add(prior.ck.Now().Sub(n.ck.Now()) + after) // the wall clock when the new daemon starts
			prior.m.mu.Lock()
			events := append([]live.Event(nil), prior.m.ev...)
			prior.m.mu.Unlock()
			if viaSnapshot {
				n.c.Restore(&live.Snapshot{Seq: events[len(events)-1].Seq, Workers: prior.c.Snapshot().Workers}, nil)
			} else {
				n.c.Restore(nil, events)
			}
			return n
		}
		// 23 hours after it was lost, a restart: still there, and the clock keeps counting from the loss
		r2 := restart(23*time.Hour, r)
		r2.c.Tick(false)
		if w, _ := counts(r2); w != 1 {
			t.Fatalf("snapshot=%v: removed before a day: %d workers", viaSnapshot, w)
		}
		r3 := restart(25*time.Hour, r) // another restart, 25 hours after the loss: gone on the first tick, not 24 hours later
		r3.c.Tick(false)
		if w, _ := counts(r3); w != 0 {
			t.Fatalf("snapshot=%v: a restart restarted the day: %d workers", viaSnapshot, w)
		}
	}
}

// C: a start recorded as ps's lstart (no zone) and read in another zone differs by whole hours: the same moment.
func TestStartInAnotherZoneIsTheSameMoment(t *testing.T) {
	at := time.Unix(1_700_000_000, 0)
	for _, zone := range []time.Duration{5 * time.Hour, -8 * time.Hour, 14 * time.Hour} {
		lstart := at.In(time.FixedZone("z", int(zone.Seconds()))).Format("Mon Jan _2 15:04:05 2006")
		r := restored(t, lstart, "1700000000.250000")
		r.c.Tick(true)
		if w, c := counts(r); w != 1 || c != 1 {
			t.Fatalf("zone %v: the worker was dropped: %d %d", zone, w, c)
		}
	}
	// minutes or seconds that differ are a different process, whatever the zone
	lstart := at.Add(90 * time.Second).In(time.FixedZone("z", 5*3600)).Format("Mon Jan _2 15:04:05 2006")
	r := restored(t, lstart, "1700000000.250000")
	r.c.Tick(true)
	if w, _ := counts(r); w != 0 {
		t.Fatal("a start 90 s apart was taken for the same moment")
	}
}
