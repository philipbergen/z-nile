package live_test

import (
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"znile/internal/live"
)

// f0420 step 4c: a silent worker's claim expires after ExpireAfter, the daemon keeps a marker for the worker that lost
// it, and the worker is told when it wakes. The owner's ruling (2026-11-22): "afetr a time and make sure a marker makes
// it clear that the worker that disappeared notices it lost the claim if it wakes up."

const (
	lostAfter   = 900 * time.Second
	expireAfter = 1800 * time.Second
)

func newExpRig() *rig {
	r := &rig{ck: &clock{t: time.Unix(1_700_000_000, 0)}, pr: newProbe(), m: &mem{}}
	r.c = live.New(live.Config{Host: "h", Now: r.ck.Now, Mono: r.ck.Mono, Sink: r.m, Probe: r.pr, LostAfter: lostAfter,
		TickEvery: 2 * time.Second, ExpireAfter: expireAfter})
	return r
}

// advance moves both clocks in 2 s steps (no step is read as a sleep), ticking the signal check at each.
func (r *rig) advance(d time.Duration) {
	for left := d; left > 0; left -= 2 * time.Second {
		step := 2 * time.Second
		if left < step {
			step = left
		}
		r.ck.Add(step)
		r.c.Tick(false)
	}
}

func losses(t *testing.T, rep live.Reply) []live.Loss {
	t.Helper()
	l, _ := rep["losses"].([]live.Loss)
	return l
}

func beat(r *rig, w string) live.Reply { return r.c.Do(live.Request{Op: "beat", Worker: w}) }

func (r *rig) eventsOf(kind string) []live.Event {
	r.m.mu.Lock()
	defer r.m.mu.Unlock()
	var out []live.Event
	for _, e := range r.m.ev {
		if e.Kind == kind {
			out = append(out, e)
		}
	}
	return out
}

// AC-exp1: a silent claim keeps excluding its unit until ExpireAfter, then frees it; the second worker is handed the unit
// and the take is recorded as taken-over.
func TestClaimExpiresAfterSilence(t *testing.T) {
	r := newExpRig()
	r.reg(t, "w1", 301, "")
	r.reg(t, "w2", 302, "")
	if rep := r.claim("w1", "u", "code"); !rep.OK() {
		t.Fatal(rep)
	}
	r.advance(expireAfter - 10*time.Second)
	if rep := r.claim("w2", "u", "code"); rep.Refused() != "held" {
		t.Fatalf("before the expiry the unit is still held: %v", rep)
	}
	// w2's own refused claim counted as hearing w2, not w1: w1 is still silent
	r.advance(20 * time.Second)
	if _, c := r.c.Counts(); c != 0 {
		t.Fatalf("the claim did not expire: %d claims", c)
	}
	exp := r.m.kinds()
	if !strings.Contains(fmt.Sprint(exp), "released/expired") {
		t.Fatalf("no released/expired event: %v", exp)
	}
	if rep := r.claim("w2", "u", "code"); !rep.OK() {
		t.Fatalf("the second worker was not handed the expired unit: %v", rep)
	}
	taken := r.eventsOf("taken-over")
	if len(taken) != 1 || taken[0].Worker != "w2" || taken[0].Unit != "u" || taken[0].Reason != "w1" {
		t.Fatalf("taken-over events: %+v", taken)
	}
	got := r.c.Losses("w1")
	if len(got) != 1 || got[0].Unit != "u" || got[0].Activity != "code" || got[0].At <= got[0].Since ||
		got[0].TakenBy != "w2" || got[0].Holder != "w2" || got[0].NoticedAt != 0 {
		t.Fatalf("w1's loss: %+v", got)
	}
}

// The default time is 1,800 s, one named value.
func TestExpireAfterDefaultIsThirtyMinutes(t *testing.T) {
	r := &rig{ck: &clock{t: time.Unix(1_700_000_000, 0)}, pr: newProbe(), m: &mem{}}
	r.c = live.New(live.Config{Host: "h", Now: r.ck.Now, Mono: r.ck.Mono, Sink: r.m, Probe: r.pr, TickEvery: 2 * time.Second})
	r.reg(t, "w", 303, "")
	r.claim("w", "u", "code")
	r.advance(1790 * time.Second)
	if _, c := r.c.Counts(); c != 1 {
		t.Fatal("expired before 1,800 s")
	}
	r.advance(20 * time.Second)
	if _, c := r.c.Counts(); c != 0 {
		t.Fatal("not expired after 1,800 s")
	}
}

// A beat inside the time keeps the claim for another full interval.
func TestBeatKeepsTheClaim(t *testing.T) {
	r := newExpRig()
	r.reg(t, "w", 304, "")
	r.claim("w", "u", "code")
	for i := 0; i < 5; i++ {
		r.advance(expireAfter - 60*time.Second)
		if rep := beat(r, "w"); !rep.OK() {
			t.Fatal(rep)
		}
	}
	if _, c := r.c.Counts(); c != 1 {
		t.Fatal("a worker that beats lost its claim")
	}
	if len(r.eventsOf("noticed")) != 0 || len(r.c.Losses("")) != 0 {
		t.Fatal("a loss was recorded for a worker that beats")
	}
}

// AC-exp2 and AC-exp3: the worker that lost the claim is told by its beat until it is acknowledged; the history stays.
func TestLateBeatToldUntilNoticed(t *testing.T) {
	r := newExpRig()
	r.reg(t, "w1", 305, "")
	r.claim("w1", "u", "review")
	r.advance(expireAfter + 10*time.Second)
	state := func() string { return r.c.Do(live.Request{Op: "workers"})["workers"].([]*live.Worker)[0].State }
	if s := state(); s != "lost" {
		t.Fatalf("an expired worker reads %q, want lost (quiet) until its beat", s)
	}
	if n := len(r.eventsOf("lost")); n != 1 {
		t.Fatalf("%d lost events for one silence, want 1 (the expiry must not reset the worker's state)", n)
	}
	rep := beat(r, "w1")
	if !rep.OK() {
		t.Fatalf("a late beat is refused: %v", rep)
	}
	if s := state(); s != "idle" {
		t.Fatalf("after its late beat the worker reads %q, want idle", s)
	}
	l := losses(t, rep)
	if len(l) != 1 || l[0].Unit != "u" || l[0].Activity != "review" || l[0].Worker != "w1" {
		t.Fatalf("the late beat does not carry the loss: %v", rep)
	}
	if again := losses(t, beat(r, "w1")); len(again) != 1 {
		t.Fatalf("told once only, before it was acknowledged: %v", again)
	}
	if rep := r.c.Do(live.Request{Op: "claims"}); len(rep["claims"].([]live.Claim)) != 0 {
		t.Fatal("the beat gave the claim back")
	}
	if rep := r.c.Do(live.Request{Op: "notice", Worker: "w1"}); !rep.OK() {
		t.Fatalf("notice: %v", rep)
	}
	if after := losses(t, beat(r, "w1")); len(after) != 0 {
		t.Fatalf("still told after the acknowledgement: %v", after)
	}
	hist := r.c.Losses("w1")
	if len(hist) != 1 || hist[0].NoticedAt == 0 {
		t.Fatalf("the history lost the told loss: %+v", hist)
	}
	if len(r.eventsOf("noticed")) != 1 {
		t.Fatal("the acknowledgement is not an event, so a restart could not replay it")
	}
	// the all-losses op shows it too
	all := r.c.Do(live.Request{Op: "losses"})
	if l := losses(t, all); len(l) != 1 {
		t.Fatalf("losses op: %v", all)
	}
}

// A new session with another worker id is never shown someone else's loss.
func TestOtherWorkerIsNotToldOfALoss(t *testing.T) {
	r := newExpRig()
	r.reg(t, "w1", 306, "")
	r.reg(t, "w3", 307, "")
	r.claim("w1", "u", "code")
	r.advance(expireAfter + 10*time.Second)
	if l := losses(t, beat(r, "w3")); len(l) != 0 {
		t.Fatalf("w3 was told of w1's loss: %v", l)
	}
	r.pr.set(308, false, "s308")
	if rep := r.c.Do(live.Request{Op: "register", CLI: "t", PID: 308}); !rep.OK() || len(losses(t, rep)) != 0 {
		t.Fatalf("a new session's register carries a loss: %v", rep)
	}
}

// A worker's expiry does not remove it, and a worker whose claim expired may hold another unit afterwards.
func TestExpiredWorkerStaysAndMayClaimAgain(t *testing.T) {
	r := newExpRig()
	r.reg(t, "w1", 309, "")
	r.claim("w1", "u", "code")
	r.advance(expireAfter + 10*time.Second)
	if w, _ := r.c.Counts(); w != 1 {
		t.Fatalf("the worker was removed: %d", w)
	}
	beat(r, "w1")
	if rep := r.claim("w1", "other", "code"); !rep.OK() {
		t.Fatalf("a revived worker cannot claim: %v", rep)
	}
}

// AC-exp2: a worker whose process ended leaves a marker too, and it survives the sweep that removes the worker; the same
// id registered again is told.
func TestEndedProcessLeavesMarker(t *testing.T) {
	r := newExpRig()
	r.pr.set(310, false, "s")
	r.reg(t, "w1", 310, "")
	r.claim("w1", "u", "code")
	r.pr.set(310, true, "")
	r.c.Tick(false)
	if w, _ := r.c.Counts(); w != 0 {
		t.Fatal("the worker was not removed")
	}
	l := r.c.Losses("w1")
	if len(l) != 1 || l[0].Unit != "u" || !strings.Contains(l[0].Reason, "process") {
		t.Fatalf("the sweep deleted or never made the marker: %+v", l)
	}
	r.pr.set(310, false, "s2")
	rep := r.c.Do(live.Request{Op: "register", Worker: "w1", CLI: "t", PID: 310})
	if !rep.OK() || len(losses(t, rep)) != 1 {
		t.Fatalf("a re-registered worker id is not told: %v", rep)
	}
}

// A new session of the same id (register replaces the old one) is not a loss to announce.
func TestReplacedSessionLeavesNoMarker(t *testing.T) {
	r := newExpRig()
	r.reg(t, "w1", 311, "sessionA")
	r.claim("w1", "u", "code")
	r.reg(t, "w1", 311, "sessionB")
	if l := r.c.Losses(""); len(l) != 0 {
		t.Fatalf("a replaced session left a marker: %+v", l)
	}
}

// AC-exp2: the marker survives a daemon restart, from the log and from the snapshot, told or not.
func TestMarkerSurvivesRestart(t *testing.T) {
	for _, viaSnapshot := range []bool{false, true} {
		for _, noticed := range []bool{false, true} {
			r := newExpRig()
			r.reg(t, "w1", 312, "s1")
			r.reg(t, "w2", 313, "s2")
			r.claim("w1", "u", "code")
			r.advance(expireAfter + 10*time.Second)
			r.claim("w2", "u", "code")
			if noticed {
				r.c.Do(live.Request{Op: "notice", Worker: "w1"})
			}
			r.m.mu.Lock()
			events := append([]live.Event(nil), r.m.ev...)
			r.m.mu.Unlock()
			n := newExpRig()
			n.pr.set(312, false, "start-312")
			n.pr.set(313, false, "start-313")
			if viaSnapshot {
				s := r.c.Snapshot()
				n.c.Restore(&s, nil)
			} else {
				n.c.Restore(nil, events)
			}
			l := n.c.Losses("w1")
			if len(l) != 1 || l[0].Unit != "u" || l[0].TakenBy != "w2" || l[0].Holder != "w2" || (l[0].NoticedAt != 0) != noticed {
				t.Fatalf("snapshot=%v noticed=%v: marker after the restart: %+v", viaSnapshot, noticed, l)
			}
			if told := losses(t, beat(n, "w1")); (len(told) == 1) == noticed {
				t.Fatalf("snapshot=%v noticed=%v: the restart changed who is told: %v", viaSnapshot, noticed, told)
			}
		}
	}
}

// AC-exp4: expiry, the take by a second worker and the late beat of the first are safe in any order: two workers never
// hold one unit, whichever wins.
func TestExpiryRaceWithBeatAndClaim(t *testing.T) {
	oldWins, newWins := 0, 0
	for round := 0; round < 200; round++ {
		r := newExpRig()
		r.reg(t, "w1", 320, "")
		r.reg(t, "w2", 321, "")
		r.claim("w1", "u", "code")
		r.advance(expireAfter - 1*time.Second)
		r.ck.Add(2 * time.Second) // w1 is now silent past the limit, but nobody has ticked yet
		var wg sync.WaitGroup
		wg.Add(3)
		start := make(chan struct{})
		go func() { defer wg.Done(); <-start; beat(r, "w1") }()
		go func() { defer wg.Done(); <-start; r.c.Tick(false) }()
		var won live.Reply
		go func() { defer wg.Done(); <-start; won = r.claim("w2", "u", "code") }()
		close(start)
		wg.Wait()
		// the log, in order, must never show a claim of a held unit, and the end state has one holder at most
		held := ""
		r.m.mu.Lock()
		for _, e := range r.m.ev {
			switch e.Kind {
			case "claimed":
				if e.Unit == "u" {
					if held != "" {
						r.m.mu.Unlock()
						t.Fatalf("round %d: %s claimed u while %s held it", round, e.Worker, held)
					}
					held = e.Worker
				}
			case "released", "gone":
				if e.Unit == "u" || e.Kind == "gone" {
					if e.Worker == held {
						held = ""
					}
				}
			}
		}
		r.m.mu.Unlock()
		holders := 0
		for _, c := range r.c.Snapshot().Claims {
			if c.Unit == "u" {
				holders++
			}
		}
		if holders > 1 {
			t.Fatalf("round %d: two holders", round)
		}
		if won.OK() {
			newWins++
			if cl := r.c.Do(live.Request{Op: "claim", Worker: "w1", Unit: "u", Activity: "code"}); cl.Refused() != "held" {
				t.Fatalf("round %d: the old worker's claim after the take: %v", round, cl)
			}
		} else {
			oldWins++
			if won.Refused() != "held" {
				t.Fatalf("round %d: refusal %v", round, won)
			}
		}
	}
	if oldWins == 0 || newWins == 0 {
		t.Logf("one side won every round (old %d, new %d): the interleavings were not mixed", oldWins, newWins)
	}
}

// A closed wait counts as heard, so a worker blocked in `wait` is never expired under it.
func TestWaiterIsNotExpired(t *testing.T) {
	r := newExpRig()
	r.reg(t, "w", 330, "")
	r.claim("w", "u", "code")
	done := make(chan live.Reply, 1)
	go func() { done <- wait(r, "w", nil, 2*time.Second) }()
	time.Sleep(100 * time.Millisecond)
	r.advance(expireAfter + 20*time.Second)
	if _, c := r.c.Counts(); c != 1 {
		t.Fatal("a worker in an open wait was expired")
	}
	<-done
}

// Told losses older than seven days are dropped when the next loss is recorded; an untold one stays.
func TestOldToldLossesAreDropped(t *testing.T) {
	r := newExpRig()
	r.reg(t, "w1", 340, "")
	r.reg(t, "w2", 341, "")
	r.claim("w1", "a", "code")
	r.claim("w2", "b", "code")
	r.advance(expireAfter + 10*time.Second)
	r.c.Do(live.Request{Op: "notice", Worker: "w1"}) // w1's is told, w2's is not
	r.ck.Add(8 * 24 * time.Hour)
	beat(r, "w1")
	r.claim("w1", "c", "code")
	r.advance(expireAfter + 10*time.Second)
	if l := r.c.Losses("w1"); len(l) != 1 || l[0].Unit != "c" {
		t.Fatalf("w1's history: %+v", l)
	}
	if l := r.c.Losses("w2"); len(l) != 1 || l[0].NoticedAt != 0 {
		t.Fatalf("an untold loss was dropped: %+v", l)
	}
}
