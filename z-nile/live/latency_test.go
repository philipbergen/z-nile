package main

import (
	"fmt"
	"os"
	"os/exec"
	"sort"
	"testing"
	"time"
)

// Run: ZNLIVE_BENCH=1 go test -run Latency -v -timeout 600s
func TestLatency(t *testing.T) {
	if os.Getenv("ZNLIVE_BENCH") == "" {
		t.Skip("set ZNLIVE_BENCH=1")
	}
	bin := build(t)
	dir := shortDir(t)
	d := exec.Command(bin, "serve", "--dir", dir, "--lost-after", "600")
	d.Start()
	defer func() { d.Process.Kill(); d.Wait() }()
	waitSock(t, dir)
	run := func(a ...string) error {
		return exec.Command(bin, append(a, "--dir", dir)...).Run()
	}
	run("register", "--worker", "waiter", "--cli", "t", "--can", "x")
	run("register", "--worker", "other", "--cli", "t", "--can", "x")
	var rel, poke []float64
	for i := 0; i < 200; i++ {
		w := exec.Command(bin, "wait", "--worker", "waiter", "--timeout", "10", "--dir", dir)
		w.Start()
		time.Sleep(150 * time.Millisecond) // let the waiter connect and block
		var t0 time.Time
		if i%2 == 0 {
			run("claim", "--worker", "other", "--unit", "R1", "--activity", "design", "--needs", "x")
			t0 = time.Now()
			run("release", "--worker", "other")
		} else {
			t0 = time.Now()
			run("poke", "--reason", "bench")
		}
		err := w.Wait()
		ms := float64(time.Since(t0).Microseconds()) / 1000
		if err != nil {
			t.Fatalf("trial %d waiter: %v", i, err)
		}
		if i%2 == 0 {
			rel = append(rel, ms)
		} else {
			poke = append(poke, ms)
		}
	}
	stats := func(n string, v []float64) {
		sort.Float64s(v)
		t.Logf("%-8s n=%d min=%.1f median=%.1f p95=%.1f max=%.1f ms", n, len(v), v[0], v[len(v)/2], v[len(v)*95/100], v[len(v)-1])
	}
	stats("release", rel)
	stats("poke", poke)
	stats("all", append(append([]float64{}, rel...), poke...))

	// no early wake: nothing relevant happens for 3 s (a claim by another worker and beats are not wake events)
	for k := 0; k < 3; k++ {
		w := exec.Command(bin, "wait", "--worker", "waiter", "--timeout", "3", "--dir", dir)
		t0 := time.Now()
		w.Start()
		time.Sleep(500 * time.Millisecond)
		run("claim", "--worker", "other", "--unit", "R2", "--activity", "design", "--needs", "x")
		run("beat", "--worker", "waiter")
		err := w.Wait()
		el := time.Since(t0)
		fmt.Printf("")
		t.Logf("idle wait %d: exit=%d elapsed=%.3fs (want 2, 3.0-3.3)", k, w.ProcessState.ExitCode(), el.Seconds())
		if err == nil || w.ProcessState.ExitCode() != 2 || el < 3*time.Second || el > 3300*time.Millisecond {
			t.Errorf("bad idle wait")
		}
		run("release", "--worker", "other")
	}
}

// Run: ZNLIVE_BENCH=1 go test -run Pairs -v
func TestPairs(t *testing.T) {
	if os.Getenv("ZNLIVE_BENCH") == "" {
		t.Skip("set ZNLIVE_BENCH=1")
	}
	bin := build(t)
	dir := shortDir(t)
	d := exec.Command(bin, "serve", "--dir", dir, "--lost-after", "600")
	d.Start()
	defer func() { d.Process.Kill(); d.Wait() }()
	waitSock(t, dir)
	run := func(a ...string) { exec.Command(bin, append(a, "--dir", dir)...).Run() }
	run("register", "--worker", "w", "--cli", "t", "--can", "x")
	var v []float64
	for i := 0; i < 100; i++ {
		t0 := time.Now()
		run("claim", "--worker", "w", "--unit", "R1", "--activity", "design", "--needs", "x")
		run("release", "--worker", "w")
		v = append(v, float64(time.Since(t0).Microseconds())/1000)
	}
	sort.Float64s(v)
	t.Logf("claim+release pair (2 process spawns) n=100 median=%.1f p95=%.1f max=%.1f ms", v[50], v[95], v[99])
}
