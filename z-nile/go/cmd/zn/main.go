// Command zn is z-nile's one program: it carries this platform's Lune and the Luau engine, extracts them once to a
// per-user cache folder and runs the engine's commands with them, so a machine needs no Lune. `zn version` runs in Go.
package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"

	"znile/internal/payload"
)

// build is stamped by the build with -ldflags -X main.build=<id>.
var build = "dev"

// Exit codes: 0 is the engine's own (it replaces this process), the others are zn's.
const (
	exitRefused     = 1
	exitUnavailable = 3
)

// deps are the things run touches outside itself, so a test can stand in for each.
type deps struct {
	embedded func() (payload.Payload, bool)
	exec     func(path string, argv, env []string) error
	env      []string
	stdout   io.Writer
	stderr   io.Writer
}

func main() {
	os.Exit(run(os.Args[1:], deps{
		embedded: payload.Embedded,
		exec:     syscall.Exec,
		env:      os.Environ(),
		stdout:   os.Stdout,
		stderr:   os.Stderr,
	}))
}

// run is zn: `version` is answered here, every other command goes to the engine under the extracted Lune. It returns
// only when something failed or the (fake) exec returned; a real exec replaces the process.
func run(args []string, d deps) int {
	p, ok := d.embedded()
	if len(args) == 1 && args[0] == "version" {
		if !ok {
			fmt.Fprintf(d.stdout, "zn %s %s/%s payload none\n", build, runtime.GOOS, runtime.GOARCH)
			return 0
		}
		id := p.ID
		if p.Dirty {
			id += "-dirty"
		}
		fmt.Fprintf(d.stdout, "zn %s %s/%s payload %s lune %s (%s pin)\n", build, runtime.GOOS, runtime.GOARCH, id, p.LuneSum(), p.Kind)
		return 0
	}
	if !ok {
		fmt.Fprintln(d.stderr, "zn: this binary has no embedded Lune and engine (it was built with a plain go build). Build it with z-nile/lib/znbuild.sh.")
		return exitUnavailable
	}
	cache, err := payload.CacheFolder(d.env)
	if err != nil {
		fmt.Fprintf(d.stderr, "zn: %v\n", err)
		return exitRefused
	}
	dir, _, err := payload.Extract(cache, p)
	if err != nil {
		fmt.Fprintf(d.stderr, "zn: %v (ZN_CACHE names another folder for the extracted engine)\n", err)
		return exitRefused
	}
	lune := filepath.Join(dir, "bin", "lune")
	argv := append([]string{lune, "run", filepath.Join(dir, "z-nile", "engine", "main"), "--"}, args...)
	if err := d.exec(lune, argv, withLuneFirst(d.env, filepath.Join(dir, "bin"))); err != nil {
		fmt.Fprintf(d.stderr, "zn: cannot run %s from the cache folder %s: %v (a noexec mount does this: set ZN_CACHE to a folder that allows running programs)\n", lune, dir, err)
		return exitRefused
	}
	return 0
}

// withLuneFirst puts the extracted Lune's folder first on PATH, so the engine's own `lune` spawns find it. An unset or
// empty PATH becomes the system default, and an empty entry (which would mean the current folder) is dropped.
func withLuneFirst(env []string, bin string) []string {
	out := make([]string, 0, len(env)+1)
	var entries []string
	for _, e := range env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			for _, part := range strings.Split(v, ":") {
				if part != "" {
					entries = append(entries, part)
				}
			}
			continue
		}
		out = append(out, e)
	}
	if len(entries) == 0 {
		entries = []string{"/usr/bin", "/bin"}
	}
	return append(out, "PATH="+bin+":"+strings.Join(entries, ":"))
}
