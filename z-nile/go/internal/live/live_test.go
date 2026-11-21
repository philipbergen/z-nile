package live_test

import (
	"context"
	"fmt"
	"sync"
	"testing"
	"time"

	"znile/internal/live"
)

type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) Now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *clock) Add(d time.Duration) {
	c.mu.Lock()
	c.t = c.t.Add(d)
	c.mu.Unlock()
}

// probe is a table of pids: alive or not, and each one's start time.
type probe struct {
	mu    sync.Mutex
	dead  map[int]bool
	start map[int]string
}

func newProbe() *probe { return &probe{dead: map[int]bool{}, start: map[int]string{}} }
func (p *probe) Alive(pid int) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return !p.dead[pid]
}
func (p *probe) Starts(pids []int) map[int]string {
	p.mu.Lock()
	defer p.mu.Unlock()
	out := map[int]string{}
	for _, pid := range pids {
		if s, ok := p.start[pid]; ok {
			out[pid] = s
		}
	}
	return out
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
	r.c = live.New(live.Config{Host: "h", Now: r.ck.Now, Sink: r.m, Probe: r.pr, LostAfter: lostAfter})
	return r
}

func (r *rig) reg(t *testing.T, id string, pid int, session string, can ...string) {
	t.Helper()
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
	r.reg(t, "a", 1, "", "design/1")
	r.reg(t, "b", 2, "")
	r.reg(t, "c", 3, "")
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
	r.reg(t, "w", 5, "s1", "design/1")
	if rep := r.claim("w", "u", "design"); !rep.OK() {
		t.Fatal(rep)
	}
	before := len(r.m.kinds())
	r.reg(t, "w", 5, "s1", "design/1")
	if n := len(r.m.kinds()); n != before {
		t.Fatalf("a repeat appended %d events: %v", n-before, r.m.kinds())
	}
	if rep := r.c.Do(live.Request{Op: "claims"}); len(rep["claims"].([]*live.Claim)) != 1 {
		t.Fatalf("claim lost: %v", rep)
	}
	r.reg(t, "w", 5, "s2", "design/1")
	got := r.m.kinds()[before:]
	want := []string{"released/lost", "gone/", "registered/"}
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("another session: %v, want %v", got, want)
	}
	if rep := r.c.Do(live.Request{Op: "claims"}); len(rep["claims"].([]*live.Claim)) != 0 {
		t.Fatalf("old claim kept: %v", rep)
	}
}

// AC4: a pid that ended, or was reused with another start time, is released (lost) and removed.
func TestDeadAndReusedPid(t *testing.T) {
	r := newRig(time.Hour)
	r.pr.set(7, false, "Mon 10:00")
	r.pr.set(8, false, "Mon 10:00")
	r.reg(t, "dead", 7, "")
	r.reg(t, "reused", 8, "")
	r.claim("dead", "u1", "design")
	r.claim("reused", "u2", "design")
	if err := r.c.Tick(true); err != nil {
		t.Fatal(err)
	}
	if w, c := r.c.Counts(); w != 2 || c != 2 {
		t.Fatalf("both alive: %d workers %d claims", w, c)
	}
	r.pr.set(7, true, "")
	r.pr.set(8, false, "Mon 11:30")
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
	r.reg(t, "w", 9, "")
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
	r.reg(t, "a", 1, "")
	r.reg(t, "b", 2, "")
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
	r.reg(t, "a", 1, "")
	r.reg(t, "b", 2, "")
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
