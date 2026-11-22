// Command znlive is the live layer: `znlive serve` is the daemon and every other subcommand is a client.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
	"time"
)

// build is stamped by the build with -ldflags -X main.build=<id>.
var build = "dev"

// Exit codes, kept from the design's contract.
const (
	exitOK          = 0
	exitRefused     = 1
	exitUsage       = 2
	exitUnavailable = 3
	exitTimeout     = 75
)

const usageText = "usage: znlive serve|register|beat|claim|release|gone|stop|workers|claims|wait|events|poke|emit|app|status|shutdown [flags]"

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }

type limits map[string]int

// String makes limits a flag.Value; the flag package prints nothing useful for it.
func (l limits) String() string { return "" }

// Set adds one class=n pair.
func (l limits) Set(v string) error {
	class, n, ok := strings.Cut(v, "=")
	k, err := strconv.Atoi(n)
	if !ok || class == "" || err != nil || k < 1 {
		return fmt.Errorf("want class=n with n at least 1, got %q", v)
	}
	l[class] = k
	return nil
}

// duration reads seconds ("30", "1.5") or a Go duration ("30s", "2m").
func duration(s string) (time.Duration, error) {
	if f, err := strconv.ParseFloat(s, 64); err == nil {
		return time.Duration(f * float64(time.Second)), nil
	}
	return time.ParseDuration(s)
}

func run(args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, usageText)
		return exitUsage
	}
	op, rest := args[0], args[1:]
	kind := ""
	if op == "emit" && len(rest) > 0 && !strings.HasPrefix(rest[0], "-") {
		kind, rest = rest[0], rest[1:]
	}
	fs := flag.NewFlagSet(op, flag.ContinueOnError)
	fs.SetOutput(stderr)
	o := &opts{limit: limits{}}
	o.bind(fs)
	if err := fs.Parse(rest); err != nil {
		return exitUsage
	}
	if fs.NArg() > 0 {
		fmt.Fprintf(stderr, "znlive %s: unexpected argument %q\n", op, fs.Arg(0))
		return exitUsage
	}
	o.visited = map[string]bool{}
	fs.Visit(func(f *flag.Flag) { o.visited[f.Name] = true })
	switch op {
	case "serve":
		return serve(o, stderr)
	case "register", "beat", "claim", "release", "gone", "stop", "workers", "claims", "wait", "events", "poke",
		"emit", "app", "status", "shutdown":
		return client(op, kind, o, stdout, stderr)
	}
	fmt.Fprintf(stderr, "znlive: unknown command %q. %s\n", op, usageText)
	return exitUsage
}
