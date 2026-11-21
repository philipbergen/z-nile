package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func die(code int, f string, a ...any) { fmt.Fprintf(os.Stderr, f+"\n", a...); os.Exit(code) }

func main() {
	if len(os.Args) < 2 {
		die(64, "usage: znlive serve|register|beat|claim|release|workers|wait|poke|events|gone [flags]")
	}
	cmd := os.Args[1]
	fs := flag.NewFlagSet(cmd, flag.ExitOnError)
	dir := fs.String("dir", ".cache/live", "state directory")
	worker := fs.String("worker", "", "worker id")
	cli := fs.String("cli", "", "cli name")
	can := fs.String("can", "", "comma list of deliverables")
	unit := fs.String("unit", "", "unit id")
	act := fs.String("activity", "", "activity")
	needs := fs.String("needs", "", "capability needed")
	outcome := fs.String("outcome", "", "done|released|failed")
	tokens := fs.Int64("tokens", 0, "tokens")
	secs := fs.Int64("seconds", 0, "seconds")
	reason := fs.String("reason", "", "poke reason")
	timeout := fs.Float64("timeout", 0, "wait timeout seconds (0 = forever)")
	follow := fs.Bool("follow", false, "events: stream")
	since := fs.Int64("since", 0, "events/wait: after this seq")
	lost := fs.Float64("lost-after", 15, "serve: seconds without beat before lost")
	at := fs.Int64("at", 0, "test aid: sleep until this unix-nano time before sending")
	fs.Parse(os.Args[2:])

	if cmd == "serve" {
		ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
		defer stop()
		s := newServer(*dir, time.Duration(*lost*float64(time.Second)))
		if err := s.serve(ctx); err != nil {
			die(1, "znlive serve: %v", err)
		}
		return
	}
	r := Req{Op: cmd, Worker: *worker, CLI: *cli, Unit: *unit, Activity: *act, Needs: *needs,
		Outcome: *outcome, Tokens: *tokens, Seconds: *secs, Reason: *reason, Since: *since, Follow: *follow}
	if *can != "" {
		r.Can = strings.Split(*can, ",")
	}
	sock := filepath.Join(*dir, "sock")
	c, err := net.Dial("unix", sock)
	if err != nil {
		die(7, "znlive: daemon not running (cannot connect to %s)", sock)
	}
	defer c.Close()
	if *at > 0 {
		time.Sleep(time.Until(time.Unix(0, *at)))
	}
	b, _ := json.Marshal(r)
	c.Write(append(b, '\n'))
	if cmd == "wait" && *timeout > 0 {
		c.SetReadDeadline(time.Now().Add(time.Duration(*timeout * float64(time.Second))))
	}
	sc := bufio.NewScanner(c)
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	code, n := 0, 0
	for sc.Scan() {
		fmt.Println(sc.Text())
		n++
		var m struct {
			Ok   *bool `json:"ok"`
			Code int   `json:"code"`
		}
		if json.Unmarshal(sc.Bytes(), &m) == nil && m.Ok != nil && !*m.Ok {
			code = m.Code
		}
	}
	if err := sc.Err(); err != nil {
		if ne, ok := err.(net.Error); ok && ne.Timeout() && cmd == "wait" {
			os.Exit(2)
		}
	}
	if (n == 0 && cmd != "workers" && cmd != "events") || (cmd == "events" && *follow) {
		die(7, "znlive: daemon connection lost (%s)", sock)
	}
	os.Exit(code)
}
