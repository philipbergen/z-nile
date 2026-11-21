package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"znile/internal/live"
	"znile/internal/where"
	"znile/internal/wire"
)

// resolveDir finds the state directory, and says whether it was named (--dir, or ZN_LIVE_DIR set by a person or a
// test) or is the default one: the main checkout's, found from the folder or set by `./zn live` itself
// (ZN_LIVE_DIR_IS_DEFAULT=1). Only a named directory may be shortened with the timing flags or keep its socket in TMPDIR.
func resolveDir(o *opts) (dir string, explicit bool, err error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", false, err
	}
	env := os.Getenv("ZN_LIVE_DIR")
	explicit = o.dir != "" || (env != "" && os.Getenv("ZN_LIVE_DIR_IS_DEFAULT") != "1")
	dir, err = where.StateDir(o.dir, env, cwd)
	return dir, explicit, err
}

// timingFlags are the daemon's own limits. They configure the one daemon everyone shares, so only a named state directory
// (a test's) may use them.
func timingFlags(o *opts) []string {
	var named []string
	for _, f := range []string{"lost-after", "idle-exit", "tick-every", "check-every", "sock-dir"} {
		if o.visited[f] {
			named = append(named, "--"+f)
		}
	}
	return named
}

// client runs one op against the daemon and maps the answer to stdout and an exit code.
func client(op, kind string, o *opts, stdout, stderr io.Writer) int {
	dir, explicit, err := resolveDir(o)
	if err != nil {
		fmt.Fprintf(stderr, "znlive %s: cannot find the state directory (%v). Run it inside the repository, or pass --dir\n", op, err)
		return exitUnavailable
	}
	if named := timingFlags(o); len(named) > 0 && !explicit {
		fmt.Fprintf(stderr, "znlive %s: %s configure the shared daemon and are for tests: use them only with --dir or ZN_LIVE_DIR naming a throwaway state directory\n", op, strings.Join(named, ", "))
		return exitUsage
	}
	var real string
	if writeOp(op) {
		real, err = where.Prepare(dir) // a write op may start the daemon, so the state directory is made
	} else {
		real, err = filepath.EvalSymlinks(dir)
	}
	if err != nil {
		fmt.Fprintf(stderr, "znlive %s: live daemon not running (no %s). Start it with znlive serve\n", op, dir)
		return exitUnavailable
	}
	r := o.request(op, kind, real)
	if msg := checkUsage(r); msg != "" {
		fmt.Fprintf(stderr, "znlive %s: %s\n", op, msg)
		return exitUsage
	}
	conn, err := wire.Dial(where.ClientSocket(real), filepath.Join(real, "lock"))
	if err != nil && writeOp(op) && !errors.Is(err, wire.ErrForeign) {
		conn, err = autostart(real, o, explicit)
	}
	if err != nil {
		if errors.Is(err, wire.ErrForeign) {
			fmt.Fprintf(stderr, "znlive %s: %v. Refusing to talk to it\n", op, err)
		} else if writeOp(op) {
			fmt.Fprintf(stderr, "znlive %s: cannot start the live daemon for %s: %v. Try znlive serve by hand\n", op, real, err)
		} else {
			fmt.Fprintf(stderr, "znlive %s: live daemon not running for %s. Start it with znlive serve\n", op, real)
		}
		return exitUnavailable
	}
	// event lines are written as they arrive, so a follow prints while it runs
	res, err := wire.Call(conn, r, wire.Patience(r), func(line []byte) error {
		_, err := stdout.Write(line)
		return err
	})
	if err != nil {
		fmt.Fprintf(stderr, "znlive %s: %v. Repeat the op; every op can be repeated\n", op, err)
		return exitUnavailable
	}
	if res.End == "timeout" {
		return exitTimeout
	}
	if res.Reply != nil && !res.Reply.OK() {
		return refusal(op, real, res, stdout, stderr)
	}
	for _, l := range res.Lines {
		stdout.Write(l)
	}
	return exitOK
}

func refusal(op, dir string, res wire.Result, stdout, stderr io.Writer) int {
	word, _ := res.Reply["refused"].(string)
	why, _ := res.Reply["why"].(string)
	switch word {
	case "timeout":
		return exitTimeout
	case "usage":
		fmt.Fprintf(stderr, "znlive %s: %s\n", op, why)
		return exitUsage
	case "dir":
		fmt.Fprintf(stderr, "znlive %s: %s. The pointer %s/socket leads to another repository's daemon: delete that file and start this repository's daemon\n", op, why, dir)
		return exitUnavailable
	case "proto":
		fmt.Fprintf(stderr, "znlive %s: %s. The daemon is from another build: it exits within 10 s of its binary being replaced, or send it SIGTERM\n", op, why)
		return exitUnavailable
	case "storage", "probe":
		fmt.Fprintf(stderr, "znlive %s: the live daemon cannot do that: %s. Fix the disk or permissions it names and repeat the op\n", op, why)
		return exitUnavailable
	case "closed":
		fmt.Fprintf(stderr, "znlive %s: the live daemon is stopping. Repeat the op\n", op)
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
