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
		id := "none"
		if ok {
			id = p.ID
		}
		fmt.Fprintf(d.stdout, "zn %s %s/%s payload %s\n", build, runtime.GOOS, runtime.GOARCH, id)
		return 0
	}
	if !ok {
		fmt.Fprintln(d.stderr, "zn: this binary has no embedded Lune and engine (it was built with a plain go build). Build it with z-nile/lib/znbuild.sh.")
		return exitUnavailable
	}
	cache, err := cacheFolder(d.env)
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
		fmt.Fprintf(d.stderr, "zn: cannot run %s: %v (a noexec mount does this: set ZN_CACHE to a folder that allows running programs)\n", lune, err)
		return exitRefused
	}
	return 0
}

// cacheFolder is where the payload is extracted: <cache>/zn, where <cache> is ZN_CACHE when set (it must be absolute),
// else XDG_CACHE_HOME when absolute, else $HOME/.cache.
func cacheFolder(env []string) (string, error) {
	get := func(k string) string {
		for _, e := range env {
			if v, ok := strings.CutPrefix(e, k+"="); ok {
				return v
			}
		}
		return ""
	}
	if v := get("ZN_CACHE"); v != "" {
		if !filepath.IsAbs(v) {
			return "", fmt.Errorf("ZN_CACHE is %q: it must be an absolute path", v)
		}
		return filepath.Join(v, "zn"), nil
	}
	if v := get("XDG_CACHE_HOME"); filepath.IsAbs(v) {
		return filepath.Join(v, "zn"), nil
	}
	if h := get("HOME"); filepath.IsAbs(h) {
		return filepath.Join(h, ".cache", "zn"), nil
	}
	return "", fmt.Errorf("no cache folder: set ZN_CACHE to an absolute path (HOME is not set)")
}

// withLuneFirst puts the extracted Lune's folder first on PATH, so the engine's own `lune` spawns find it.
func withLuneFirst(env []string, bin string) []string {
	out := make([]string, 0, len(env)+1)
	done := false
	for _, e := range env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			e = "PATH=" + bin + ":" + v
			done = true
		}
		out = append(out, e)
	}
	if !done {
		out = append(out, "PATH="+bin)
	}
	return out
}
