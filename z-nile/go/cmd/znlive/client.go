package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"znile/internal/live"
	"znile/internal/where"
	"znile/internal/wire"
)

func resolveDir(o *opts) (string, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return where.StateDir(o.dir, os.Getenv("ZN_LIVE_DIR"), cwd)
}

// client runs one op against the daemon and maps the answer to stdout and an exit code.
func client(op, kind string, o *opts, stdout, stderr io.Writer) int {
	dir, err := resolveDir(o)
	if err != nil {
		fmt.Fprintf(stderr, "znlive %s: cannot find the state directory (%v). Run it inside the repository, or pass --dir\n", op, err)
		return exitUnavailable
	}
	real, err := filepath.EvalSymlinks(dir)
	if err != nil {
		fmt.Fprintf(stderr, "znlive %s: live daemon not running (no %s). Start it with znlive serve\n", op, dir)
		return exitUnavailable
	}
	r := o.request(op, kind, real)
	if msg := checkUsage(r); msg != "" {
		fmt.Fprintf(stderr, "znlive %s: %s\n", op, msg)
		return exitUsage
	}
	conn, err := wire.Dial(where.ClientSocket(real))
	if err != nil {
		fmt.Fprintf(stderr, "znlive %s: live daemon not running for %s. Start it with znlive serve\n", op, real)
		return exitUnavailable
	}
	res, err := wire.Call(conn, r, wire.Patience(r))
	if err != nil {
		fmt.Fprintf(stderr, "znlive %s: %v. Repeat the op; every op can be repeated\n", op, err)
		return exitUnavailable
	}
	if res.End == "timeout" {
		return exitTimeout
	}
	if res.Reply != nil && !res.Reply.OK() {
		return refusal(op, res, stdout, stderr)
	}
	for _, l := range res.Lines {
		stdout.Write(l)
	}
	return exitOK
}

func refusal(op string, res wire.Result, stdout, stderr io.Writer) int {
	word, _ := res.Reply["refused"].(string)
	why, _ := res.Reply["why"].(string)
	switch word {
	case "timeout":
		return exitTimeout
	case "usage":
		fmt.Fprintf(stderr, "znlive %s: %s\n", op, why)
		return exitUsage
	case "dir", "proto":
		fmt.Fprintf(stderr, "znlive %s: %s. Run ./zn live shutdown and retry\n", op, why)
		return exitUnavailable
	}
	for _, l := range res.Lines {
		stdout.Write(l)
	}
	fmt.Fprintf(stderr, "znlive %s: refused %s: %s\n", op, word, why)
	return exitRefused
}

// checkUsage catches a request that cannot work, before any connection is made.
func checkUsage(r live.Request) string {
	need := func(ok bool, what string) string {
		if ok {
			return ""
		}
		return what
	}
	switch r.Op {
	case "register":
		return need(r.CLI != "" && r.PID > 0, "register needs --cli and --pid")
	case "beat", "gone", "stop", "release", "wait":
		return need(r.Worker != "", r.Op+" needs --worker (or ZN_WORKER)")
	case "claim":
		return need(r.Worker != "" && r.Unit != "" && r.Activity != "", "claim needs --worker, --unit and --activity")
	case "emit":
		return need(r.Kind != "", "emit needs a kind: znlive emit <kind> [flags]")
	}
	return ""
}
