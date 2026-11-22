package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"znile/internal/live"
	"znile/internal/where"
	"znile/internal/wire"
)

// resolveDir finds the state directory, and says whether it is a named one (a test's) or the default: the main checkout's
// <root>/.cache/live, whichever way it was spelled (found from the folder, ZN_LIVE_DIR, --dir or through a symlink: where.IsDefaultDir
// compares the real paths). Only a named directory may be shortened with the timing flags or keep its socket in TMPDIR.
func resolveDir(o *opts) (dir string, named bool, err error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", false, err
	}
	// a relative ZN_LIVE_DIR would mean a different directory in every folder a command runs from
	if env := os.Getenv("ZN_LIVE_DIR"); o.dir == "" && env != "" && !filepath.IsAbs(env) {
		return "", false, fmt.Errorf("ZN_LIVE_DIR=%q is not absolute: name the state directory by its full path", env)
	}
	dir, err = where.StateDir(o.dir, os.Getenv("ZN_LIVE_DIR"), cwd)
	if err != nil {
		return "", false, err
	}
	isDefault := where.IsDefaultDir(dir, cwd)
	// a check (the spec fence, a probe under ./zn run) never reaches the real repository's live state
	if isDefault && os.Getenv("ZN_LIVE_ALLOW_DEFAULT") != "1" {
		for _, marker := range []string{"PICKMAN_FENCE_SPECS", "PICKMAN_TEST_FENCE", "ZN_BOUNDED_DEADLINE"} {
			if os.Getenv(marker) != "" {
				return "", false, fmt.Errorf("refusing the repository's own state directory %s: %s is set, so this is a check or a probe. Name a throwaway directory with ZN_LIVE_DIR (or ZN_LIVE_ALLOW_DEFAULT=1 to mean it)", dir, marker)
			}
		}
	}
	return dir, !isDefault, nil
}

// callBudget is the hard limit of a one-shot op (every op but wait and a follow): the call ends with exit 3 when it has not
// finished by then. Go ignores SIGALRM and a stopped daemon accepts a connection and never answers, so the limit is the
// client's own. ZN_LIVE_CALL_BUDGET (seconds) sets it; the default is 2.
func callBudget() time.Duration {
	if v := os.Getenv("ZN_LIVE_CALL_BUDGET"); v != "" {
		if d, err := time.ParseDuration(v + "s"); err == nil && d > 0 {
			return d
		}
	}
	return 2 * time.Second
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
	if op != "wait" && !o.follow {
		budget := callBudget()
		time.AfterFunc(budget, func() {
			fmt.Fprintf(stderr, "znlive %s: no answer in %v: the live layer is unavailable (a stopped or stuck daemon)\n", op, budget)
			os.Exit(exitUnavailable)
		})
	}
	dir, named, err := resolveDir(o)
	if err != nil {
		fmt.Fprintf(stderr, "znlive %s: cannot find the state directory (%v). Run it inside the repository, or pass --dir\n", op, err)
		return exitUnavailable
	}
	if flagged := timingFlags(o); len(flagged) > 0 && !named {
		fmt.Fprintf(stderr, "znlive %s: %s configure the shared daemon and are for tests: use them only with --dir or ZN_LIVE_DIR naming a throwaway state directory\n", op, strings.Join(flagged, ", "))
		return exitUsage
	}
	var real string
	// ZN_LIVE_NO_START=1 (set by the Luau caller inside an agent's sandbox): a write op is told to a daemon that runs and
	// never starts one, so it makes no state directory either
	mayStart := writeOp(op) && os.Getenv("ZN_LIVE_NO_START") != "1"
	if mayStart {
		real, err = where.Prepare(dir) // a write op may start the daemon, so the state directory is made
	} else {
		real, err = filepath.EvalSymlinks(dir)
	}
	if err != nil {
		fmt.Fprintf(stderr, "znlive %s: live daemon not running (no %s). The first write (register, claim, emit, ...) starts it\n", op, dir)
		return exitUnavailable
	}
	r := o.request(op, kind, real)
	if msg := checkUsage(r); msg != "" {
		fmt.Fprintf(stderr, "znlive %s: %s\n", op, msg)
		return exitUsage
	}
	if op == "app" {
		page, err := appPage(o.page)
		if err != nil {
			fmt.Fprintf(stderr, "znlive app: %v\n", err)
			return exitUnavailable
		}
		r.Page = page
	}
	conn, err := wire.Dial(where.ClientSocket(real), filepath.Join(real, "lock"))
	if err != nil && mayStart && !errors.Is(err, wire.ErrForeign) {
		conn, err = autostart(real, o, named)
	}
	if err != nil {
		if errors.Is(err, wire.ErrForeign) {
			fmt.Fprintf(stderr, "znlive %s: %v. Refusing to talk to it\n", op, err)
		} else if writeOp(op) {
			fmt.Fprintf(stderr, "znlive %s: cannot start the live daemon for %s: %v. Try znlive serve by hand\n", op, real, err)
		} else {
			fmt.Fprintf(stderr, "znlive %s: live daemon not running for %s. The first write (register, claim, emit, ...) starts it\n", op, real)
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
	if op == "app" {
		url, _ := res.Reply["url"].(string)
		fmt.Fprintln(stdout, url)
		return exitOK
	}
	for _, l := range res.Lines {
		stdout.Write(l)
	}
	return exitOK
}

// appPage is the absolute path of the app page: the flag, else z-nile/app/index.html of the main checkout (ZN_LIVE_ROOT, else
// the repository the command runs in). The file must exist, because the daemon reads it for every request.
func appPage(flagVal string) (string, error) {
	p := flagVal
	if p == "" {
		root := os.Getenv("ZN_LIVE_ROOT")
		if root == "" {
			cwd, err := os.Getwd()
			if err == nil {
				root, err = where.MainCheckout(cwd)
			}
			if err != nil {
				return "", fmt.Errorf("cannot find the app page (%v). Run it inside the repository, or pass --page", err)
			}
		}
		p = filepath.Join(root, "z-nile", "app", "index.html")
	}
	p, err := filepath.Abs(p)
	if err != nil {
		return "", err
	}
	if st, err := os.Stat(p); err != nil || !st.Mode().IsRegular() {
		return "", fmt.Errorf("the app page %s is not a file. Pass --page, or run it where z-nile/app/index.html exists", p)
	}
	return p, nil
}

func refusal(op, dir string, res wire.Result, stdout, stderr io.Writer) int {
	word, _ := res.Reply["refused"].(string)
	why, _ := res.Reply["why"].(string)
	switch word {
	case "timeout":
		return exitTimeout
	case "usage":
		if strings.HasPrefix(why, "unknown op ") {
			fmt.Fprintf(stderr, "znlive %s: the running daemon is an older build that does not know %s. It exits within 10 s of a rebuild: repeat the command (./zn live build rebuilds)\n", op, op)
			return exitUnavailable
		}
		fmt.Fprintf(stderr, "znlive %s: %s\n", op, why)
		return exitUsage
	case "page":
		fmt.Fprintf(stderr, "znlive %s: refused the page: %s\n", op, why)
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
	case "http":
		fmt.Fprintf(stderr, "znlive %s: %s\n", op, why)
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
	case "beat":
		return need(r.Worker != "" || (r.CLI != "" && r.PID > 0), "beat needs --worker (or ZN_WORKER), or --cli and --pid")
	case "gone", "stop", "release", "wait":
		return need(r.Worker != "", r.Op+" needs --worker (or ZN_WORKER)")
	case "claim":
		return need(r.Worker != "" && r.Unit != "" && r.Activity != "", "claim needs --worker, --unit and --activity")
	case "emit":
		return need(r.Kind != "", "emit needs a kind: znlive emit <kind> [flags]")
	case "app":
		return need(r.Port >= 0 && r.Port <= 65535, "app needs --port between 0 and 65535")
	}
	return ""
}
