package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

func call(dir string, r Req) (map[string]any, error) {
	c, err := net.Dial("unix", filepath.Join(dir, "sock"))
	if err != nil {
		return nil, err
	}
	defer c.Close()
	b, _ := json.Marshal(r)
	c.Write(append(b, '\n'))
	line, err := bufio.NewReader(c).ReadBytes('\n')
	if err != nil {
		return nil, err
	}
	m := map[string]any{}
	json.Unmarshal(line, &m)
	return m, nil
}

func waitSock(t *testing.T, dir string) {
	for i := 0; i < 200; i++ {
		if c, err := net.Dial("unix", filepath.Join(dir, "sock")); err == nil {
			c.Close()
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal("daemon did not start")
}

func TestRaceGoroutines(t *testing.T) {
	dir := shortDir(t)
	s := newServer(dir, time.Minute)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- s.serve(ctx) }()
	defer func() { cancel(); <-done }()
	waitSock(t, dir)
	const N, R = 50, 200
	for i := 0; i < N; i++ {
		call(dir, Req{Op: "register", Worker: fmt.Sprint("w", i), CLI: "t", Can: []string{"x"}})
	}
	wins, refusals, errs := 0, 0, 0
	for r := 0; r < R; r++ {
		gate := make(chan struct{})
		var mu sync.Mutex
		var wg sync.WaitGroup
		w, ref := 0, 0
		winner := ""
		for i := 0; i < N; i++ {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()
				<-gate
				m, err := call(dir, Req{Op: "claim", Worker: fmt.Sprint("w", i), Unit: "R0099", Activity: "design", Needs: "x"})
				mu.Lock()
				defer mu.Unlock()
				switch {
				case err != nil:
					errs++
				case m["ok"] == true:
					w++
					winner = fmt.Sprint("w", i)
				case m["code"] == float64(3):
					ref++
				default:
					errs++
				}
			}(i)
		}
		close(gate)
		wg.Wait()
		if w != 1 || ref != N-1 {
			t.Fatalf("round %d: winners=%d refusals=%d", r, w, ref)
		}
		wins += w
		refusals += ref
		call(dir, Req{Op: "release", Worker: winner})
	}
	t.Logf("goroutines: rounds=%d claimants=%d total_winners=%d total_refusals=%d errors=%d (exactly one winner each round)", R, N, wins, refusals, errs)
	if errs != 0 {
		t.Fatal("errors")
	}
}

func build(t *testing.T) string {
	bin := filepath.Join(t.TempDir(), "znlive")
	if out, err := exec.Command("go", "build", "-o", bin, ".").CombinedOutput(); err != nil {
		t.Fatalf("%v %s", err, out)
	}
	return bin
}

func TestRaceProcesses(t *testing.T) {
	bin := build(t)
	dir := shortDir(t)
	d := exec.Command(bin, "serve", "--dir", dir, "--lost-after", "300")
	if err := d.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() { d.Process.Kill(); d.Wait() }()
	waitSock(t, dir)
	const N, R = 20, 50
	for i := 0; i < N; i++ {
		if out, err := exec.Command(bin, "register", "--dir", dir, "--worker", fmt.Sprint("p", i), "--cli", "t", "--can", "x").CombinedOutput(); err != nil {
			t.Fatalf("%v %s", err, out)
		}
	}
	tw, tr, te := 0, 0, 0
	for r := 0; r < R; r++ {
		at := fmt.Sprint(time.Now().Add(250 * time.Millisecond).UnixNano())
		cmds := make([]*exec.Cmd, N)
		for i := range cmds {
			cmds[i] = exec.Command(bin, "claim", "--dir", dir, "--worker", fmt.Sprint("p", i), "--unit", "R0099", "--activity", "design", "--needs", "x", "--at", at)
			cmds[i].Start()
		}
		w, ref, e, winner := 0, 0, 0, ""
		for i, c := range cmds {
			err := c.Wait()
			switch code := c.ProcessState.ExitCode(); {
			case err == nil:
				w++
				winner = fmt.Sprint("p", i)
			case code == 3:
				ref++
			default:
				e++
			}
		}
		if w != 1 || ref != N-1 || e != 0 {
			t.Fatalf("round %d: winners=%d refusals=%d errors=%d", r, w, ref, e)
		}
		tw += w
		tr += ref
		te += e
		if out, err := exec.Command(bin, "release", "--dir", dir, "--worker", winner).CombinedOutput(); err != nil {
			t.Fatalf("%v %s", err, out)
		}
	}
	t.Logf("processes: rounds=%d claimant_processes=%d total_winners=%d total_refusals=%d errors=%d (exactly one winner each round)", R, N, tw, tr, te)
}

func TestSecondDaemonRefusedAndStaleSocket(t *testing.T) {
	bin := build(t)
	dir := shortDir(t)
	d := exec.Command(bin, "serve", "--dir", dir)
	d.Start()
	waitSock(t, dir)
	out, err := exec.Command(bin, "serve", "--dir", dir).CombinedOutput()
	if err == nil {
		t.Fatalf("second daemon started: %s", out)
	}
	t.Logf("second daemon: %s", out)
	d.Process.Kill()
	d.Wait()
	if _, err := os.Stat(filepath.Join(dir, "sock")); err != nil {
		t.Fatal("expected stale socket after kill -9")
	}
	d2 := exec.Command(bin, "serve", "--dir", dir)
	d2.Start()
	defer func() { d2.Process.Kill(); d2.Wait() }()
	waitSock(t, dir)
}

// unix socket paths are limited to ~104 bytes on macOS; t.TempDir() embeds the test name and can exceed it.
func shortDir(t *testing.T) string {
	d, err := os.MkdirTemp("", "zl")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(d) })
	return d
}
