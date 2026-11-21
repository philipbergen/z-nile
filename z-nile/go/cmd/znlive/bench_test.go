package main

import (
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"testing"
	"time"
)

// The measurements are opt-in: ZN_LIVE_BENCH=1, run by hand under `./zn run --time 600 -- go test ...`.

func benchRig(t *testing.T) *rig {
	t.Helper()
	if os.Getenv("ZN_LIVE_BENCH") != "1" {
		t.Skip("set ZN_LIVE_BENCH=1")
	}
	r := newRig(t)
	r.serve(r.dir, "--lost-after", "600s")
	me := fmt.Sprint(os.Getpid())
	for _, w := range []string{"waiter", "other"} {
		r.zn(r.dir, "register", "--worker", w, "--cli", "t", "--pid", me, "--can", "x/1")
	}
	return r
}

func stats(t *testing.T, name string, v []float64) {
	sort.Float64s(v)
	t.Logf("%-10s n=%d min=%.1f median=%.1f p95=%.1f max=%.1f ms", name, len(v), v[0], v[len(v)/2], v[len(v)*95/100], v[len(v)-1])
}

// Wake latency: a waiter blocked in `znlive wait`, then a release or a poke from another process.
func TestBenchWakeLatency(t *testing.T) {
	r := benchRig(t)
	var rel, poke []float64
	for i := 0; i < 200; i++ {
		w := exec.Command(binary, "wait", "--dir", r.dir, "--worker", "waiter", "--timeout", "10")
		w.Env = r.env()
		w.Start()
		time.Sleep(150 * time.Millisecond) // let the waiter connect and block
		var t0 time.Time
		if i%2 == 0 {
			r.zn(r.dir, "claim", "--worker", "other", "--unit", "R1", "--activity", "design")
			t0 = time.Now()
			r.zn(r.dir, "release", "--worker", "other")
		} else {
			t0 = time.Now()
			r.zn(r.dir, "poke", "--reason", "bench")
		}
		if err := w.Wait(); err != nil {
			t.Fatalf("trial %d: %v", i, err)
		}
		ms := float64(time.Since(t0).Microseconds()) / 1000
		if i%2 == 0 {
			rel = append(rel, ms)
		} else {
			poke = append(poke, ms)
		}
	}
	stats(t, "release", rel)
	stats(t, "poke", poke)
	stats(t, "all", append(append([]float64{}, rel...), poke...))
}

// A claim and a release from a shell, two process starts.
func TestBenchClaimReleasePair(t *testing.T) {
	r := benchRig(t)
	var v []float64
	for i := 0; i < 100; i++ {
		t0 := time.Now()
		r.zn(r.dir, "claim", "--worker", "other", "--unit", "R1", "--activity", "design")
		r.zn(r.dir, "release", "--worker", "other")
		v = append(v, float64(time.Since(t0).Microseconds())/1000)
	}
	stats(t, "pair", v)
}

// Idle cost: five blocked waiters and a daemon for 120 s; the daemon's CPU time is read from ps.
func TestBenchIdleCPU(t *testing.T) {
	r := benchRig(t)
	d := r.pids[0].Process.Pid
	for i := 0; i < 5; i++ {
		w := exec.Command(binary, "wait", "--dir", r.dir, "--worker", "waiter", "--timeout", "150")
		w.Env = r.env()
		w.Start()
		t.Cleanup(func() { w.Process.Kill(); w.Wait() })
	}
	cpu := func() float64 {
		out, err := exec.Command("ps", "-o", "time=", "-p", fmt.Sprint(d)).Output()
		if err != nil {
			t.Fatal(err)
		}
		f := strings.TrimSpace(string(out)) // [[dd-]hh:]mm:ss.ss
		var s float64
		for _, part := range strings.Split(strings.ReplaceAll(f, "-", ":"), ":") {
			x, _ := strconv.ParseFloat(part, 64)
			s = s*60 + x
		}
		return s
	}
	time.Sleep(2 * time.Second)
	before := cpu()
	time.Sleep(120 * time.Second)
	t.Logf("daemon CPU over 120 s idle with 5 waiters: %.2f s", cpu()-before)
}
