package store_test

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"znile/internal/live"
	"znile/internal/store"
)

type clock struct {
	t    time.Time
	mono time.Duration
}

func (c *clock) Now() time.Time      { return c.t }
func (c *clock) Mono() time.Duration { return c.mono }
func (c *clock) add(d time.Duration) { c.t, c.mono = c.t.Add(d), c.mono+d }

func open(t *testing.T, dir string, ck *clock, lostAfter time.Duration) (*live.Core, *store.Store) {
	t.Helper()
	st, snap, events, err := store.Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	core := live.New(live.Config{Host: "h", Now: ck.Now, Mono: ck.Mono, Sink: st, LostAfter: lostAfter})
	core.Restore(snap, events)
	return core, st
}

func mustOK(t *testing.T, rep live.Reply) live.Reply {
	t.Helper()
	if !rep.OK() {
		t.Fatalf("refused: %v", rep)
	}
	return rep
}

func seed(t *testing.T, c *live.Core) {
	t.Helper()
	mustOK(t, c.Do(live.Request{Op: "register", Worker: "a", CLI: "t", PID: 104, Can: []string{"x/1"}}))
	mustOK(t, c.Do(live.Request{Op: "register", Worker: "b", CLI: "t", PID: 105}))
	mustOK(t, c.Do(live.Request{Op: "claim", Worker: "a", Unit: "u", Activity: "design", Tags: live.Tags{Raft: "R1", Round: 2}}))
}

// AC7: after a crash (no snapshot) and a restart the workers, claims and next seq are back, and nobody is lost
// before lost-after has passed since the restart.
func TestRestartRestoresState(t *testing.T) {
	dir := t.TempDir()
	ck := &clock{t: time.Unix(1_700_000_000, 0)}
	c1, st1 := open(t, dir, ck, 100*time.Second)
	seed(t, c1)
	seq := c1.Snapshot().Seq
	st1.Close() // a kill -9 leaves the log as written; Close only frees the descriptor
	ck.add(10 * time.Hour)
	c2, st2 := open(t, dir, ck, 100*time.Second)
	defer st2.Close()
	snap := c2.Snapshot()
	if snap.Seq != seq || len(snap.Workers) != 2 || len(snap.Claims) != 1 {
		t.Fatalf("restored %+v, want seq %d, 2 workers, 1 claim", snap, seq)
	}
	if cl := snap.Claims[0]; cl.Worker != "a" || cl.Raft != "R1" || cl.Round != 2 || cl.Activity != "design" {
		t.Fatalf("claim %+v", cl)
	}
	if snap.Workers[0].Can[0] != "x/1" {
		t.Fatalf("worker %+v", snap.Workers[0])
	}
	ck.add(99 * time.Second)
	if err := c2.Tick(false); err != nil {
		t.Fatal(err)
	}
	for _, w := range c2.Snapshot().Workers {
		if w.State == "lost" {
			t.Fatalf("%s lost 99 s after the restart", w.ID)
		}
	}
	ck.add(2 * time.Second)
	if err := c2.Tick(false); err != nil {
		t.Fatal(err)
	}
	if n := len(c2.Snapshot().Workers); n != 2 {
		t.Fatalf("workers %d", n)
	}
	for _, w := range c2.Snapshot().Workers {
		if w.State != "lost" {
			t.Fatalf("%s is %s 101 s after the restart", w.ID, w.State)
		}
	}
	rep := mustOK(t, c2.Do(live.Request{Op: "poke"}))
	if rep["seq"] != seq+3 { // two losts and the poke
		t.Fatalf("next seq %v, want %d", rep["seq"], seq+3)
	}
}

// The snapshot written at exit and the events after it give the same state as the whole log.
func TestSnapshotThenEvents(t *testing.T) {
	dir := t.TempDir()
	ck := &clock{t: time.Unix(1_700_000_000, 0)}
	c1, st1 := open(t, dir, ck, time.Hour)
	seed(t, c1)
	if err := st1.WriteSnapshot(c1.Snapshot()); err != nil {
		t.Fatal(err)
	}
	mustOK(t, c1.Do(live.Request{Op: "release", Worker: "a", Outcome: "done"}))
	mustOK(t, c1.Do(live.Request{Op: "claim", Worker: "b", Unit: "v", Activity: "fix"}))
	want := c1.Snapshot()
	st1.Close()
	c2, st2 := open(t, dir, ck, time.Hour)
	defer st2.Close()
	got := c2.Snapshot()
	if got.Seq != want.Seq || len(got.Claims) != 1 || got.Claims[0].Unit != "v" || len(got.Workers) != 2 {
		t.Fatalf("got %+v want %+v", got, want)
	}
	if n := len(c2.EventsSince(0, "")); int64(n) != want.Seq {
		t.Fatalf("%d events, want %d", n, want.Seq)
	}
}

// AC8: a torn last line is truncated to the last newline, repaired is 1, and the next event is a whole line.
func TestTornTailRepaired(t *testing.T) {
	dir := t.TempDir()
	ck := &clock{t: time.Unix(1_700_000_000, 0)}
	c1, st1 := open(t, dir, ck, time.Hour)
	seed(t, c1)
	st1.Close()
	log := filepath.Join(dir, "events.jsonl")
	f, err := os.OpenFile(log, os.O_APPEND|os.O_WRONLY, 0)
	if err != nil {
		t.Fatal(err)
	}
	f.WriteString(`{"seq":99,"at":1,"kind":"po`)
	f.Close()
	before, _ := os.ReadFile(log)
	c2, st2 := open(t, dir, ck, time.Hour)
	defer st2.Close()
	if st2.Repaired != 1 {
		t.Fatalf("repaired %d", st2.Repaired)
	}
	after, _ := os.ReadFile(log)
	if len(after) >= len(before) || after[len(after)-1] != '\n' {
		t.Fatalf("not truncated: %d -> %d bytes", len(before), len(after))
	}
	rep := mustOK(t, c2.Do(live.Request{Op: "poke", Reason: "next"}))
	if rep["seq"] != int64(4) {
		t.Fatalf("seq %v, want 4 (the torn line was never an event)", rep["seq"])
	}
	st2.Close()
	st3, _, ev, err := store.Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer st3.Close()
	if len(ev) != 4 {
		t.Fatalf("%d events after the repair and one append, want 4", len(ev))
	}
}

// A bad line that is not the last is skipped and counted, and the events around it survive.
func TestBadMiddleLineSkipped(t *testing.T) {
	dir := t.TempDir()
	log := filepath.Join(dir, "events.jsonl")
	body := `{"seq":1,"at":1,"kind":"poke"}` + "\nnot json\n" + `{"seq":2,"at":2,"kind":"poke"}` + "\n"
	if err := os.WriteFile(log, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	st, _, ev, err := store.Open(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	if len(ev) != 2 || st.Skipped != 1 || st.Repaired != 0 {
		t.Fatalf("events %d skipped %d repaired %d", len(ev), st.Skipped, st.Repaired)
	}
}
