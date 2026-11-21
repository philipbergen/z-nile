// Package where finds the state directory, the socket and the processes the live layer talks about.
package where

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"znile/internal/live"
)

// ErrNoRepo is returned when no main checkout can be found from the folder.
var ErrNoRepo = errors.New("not inside a repository's main or linked checkout")

// StateDir returns the state directory: flag, else env, else <main checkout>/.cache/live found by walking up from cwd.
func StateDir(flag, env, cwd string) (string, error) {
	if flag != "" {
		return filepath.Abs(flag)
	}
	if env != "" {
		return filepath.Abs(env)
	}
	main, err := MainCheckout(cwd)
	if err != nil {
		return "", err
	}
	return filepath.Join(main, ".cache", "live"), nil
}

// MainCheckout walks up from cwd to the first .git. A folder is the main checkout's. A gitdir: file leads through
// that folder's commondir file to the main checkout. Anything else is ErrNoRepo. No git process is started.
func MainCheckout(cwd string) (string, error) {
	dir, err := filepath.Abs(cwd)
	if err != nil {
		return "", err
	}
	for {
		g := filepath.Join(dir, ".git")
		st, err := os.Lstat(g)
		switch {
		case err == nil && st.IsDir():
			return dir, nil
		case err == nil && st.Mode().IsRegular():
			return mainFromFile(g)
		}
		up := filepath.Dir(dir)
		if up == dir {
			return "", ErrNoRepo
		}
		dir = up
	}
}

func mainFromFile(g string) (string, error) {
	b, err := os.ReadFile(g)
	if err != nil {
		return "", err
	}
	gd, ok := strings.CutPrefix(strings.TrimSpace(string(b)), "gitdir:")
	if !ok {
		return "", ErrNoRepo
	}
	gd = strings.TrimSpace(gd)
	if !filepath.IsAbs(gd) {
		gd = filepath.Join(filepath.Dir(g), gd)
	}
	cb, err := os.ReadFile(filepath.Join(gd, "commondir"))
	if err != nil {
		return "", ErrNoRepo
	}
	common := strings.TrimSpace(string(cb))
	if !filepath.IsAbs(common) {
		common = filepath.Join(gd, common)
	}
	return filepath.Dir(filepath.Clean(common)), nil
}

// Prepare creates the state directory (mode 0700) and returns its real path.
func Prepare(dir string) (string, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return "", err
	}
	if err := os.Chmod(dir, 0o700); err != nil {
		return "", err
	}
	return filepath.EvalSymlinks(dir)
}

// SocketPath is <tmp>/zl-<uid>-<h>.sock in the current TMPDIR (SocketPathIn), h being 12 hex of the sha256 of the state
// directory's real path; /tmp when the first is over 100 bytes.
func SocketPath(realDir string) string { return SocketPathIn(os.TempDir(), realDir) }

// SocketPathIn is the socket's path in the folder dir (the same /tmp fallback for a path over 100 bytes).
func SocketPathIn(dir, realDir string) string {
	sum := sha256.Sum256([]byte(realDir))
	name := fmt.Sprintf("zl-%d-%s.sock", os.Getuid(), hex.EncodeToString(sum[:])[:12])
	p := filepath.Join(dir, name)
	if len(p) > 100 {
		p = filepath.Join("/tmp", name)
	}
	return p
}

var (
	stableOnce sync.Once
	stableDir  string
	stableErr  error
)

// StableDir is the folder of the default state directory's socket, which does not depend on the process that asks: on
// macOS the user's temp folder (confstr _CS_DARWIN_USER_TEMP_DIR, which `getconf DARWIN_USER_TEMP_DIR` prints; asked
// once, from a process that sets no TMPDIR), elsewhere /tmp/zl-<uid>, made 0700 and refused when it belongs to another
// user or is open to others.
func StableDir() (string, error) {
	stableOnce.Do(func() { stableDir, stableErr = stableDirNow() })
	return stableDir, stableErr
}

func stableDirNow() (string, error) {
	if runtime.GOOS == "darwin" {
		cmd := exec.Command("getconf", "DARWIN_USER_TEMP_DIR")
		cmd.Env = []string{"PATH=/usr/bin:/bin"}
		out, err := cmd.Output()
		d := filepath.Clean(strings.TrimSpace(string(out)))
		if err == nil && filepath.IsAbs(d) && d != "/" {
			return d, nil
		}
	}
	d := filepath.Join("/tmp", fmt.Sprintf("zl-%d", os.Getuid()))
	if err := os.Mkdir(d, 0o700); err != nil && !errors.Is(err, os.ErrExist) {
		return "", err
	}
	st, err := os.Lstat(d)
	if err != nil {
		return "", err
	}
	sys, ok := st.Sys().(*syscall.Stat_t)
	if !st.IsDir() || !ok || int(sys.Uid) != os.Getuid() || st.Mode().Perm()&0o077 != 0 {
		return "", fmt.Errorf("%s is not a private folder of this user (mode %v): remove it", d, st.Mode())
	}
	return d, nil
}

// SocketDir is the folder the socket goes in. A test names it with override (a folder, or "stable" to force the default
// rule). A state directory named by --dir or ZN_LIVE_DIR (explicit: specs and tests use their own) keeps its socket in the
// current TMPDIR, where a spec jail can create it; the default state directory, the main checkout's, uses StableDir.
func SocketDir(explicit bool, override string) (string, error) {
	switch {
	case override == "stable":
		return StableDir()
	case override != "":
		return override, nil
	case explicit:
		return os.TempDir(), nil
	}
	return StableDir()
}

// ClientSocket is the path in <state>/socket, which a client with another TMPDIR still finds, else the default rule's.
func ClientSocket(realDir string) string {
	if b, err := os.ReadFile(filepath.Join(realDir, "socket")); err == nil && len(b) > 0 {
		return strings.TrimSpace(string(b))
	}
	d, err := SocketDir(false, os.Getenv("ZN_LIVE_SOCKDIR"))
	if err != nil {
		d = os.TempDir()
	}
	return SocketPathIn(d, realDir)
}

// OSProbe looks at real processes: signal 0 for liveness, ps for start times.
type OSProbe struct{}

// Alive reports whether the pid exists; permission denied counts as alive.
func (OSProbe) Alive(pid int) bool {
	err := syscall.Kill(pid, 0)
	return err == nil || errors.Is(err, syscall.EPERM)
}

// Procs asks the kernel (macOS) or ps about the pids in one call: the start time and whether the process is a zombie. A pid ps does not
// know is absent. An error means ps itself could not run.
func (OSProbe) Procs(pids []int) (map[int]live.Proc, error) {
	if len(pids) == 0 {
		return nil, nil
	}
	if res, err := sysctlProcs(pids); err == nil { // macOS: no process to start, and it works inside a sandbox
		return res, nil
	}
	return psProcs(pids)
}

// psProcs asks ps about the pids in one call.
func psProcs(pids []int) (map[int]live.Proc, error) {
	list := make([]string, len(pids))
	for i, p := range pids {
		list[i] = strconv.Itoa(p)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "ps", "-o", "pid=,stat=,lstart=", "-p", strings.Join(list, ",")).Output()
	var ee *exec.ExitError
	if err != nil && !(errors.As(err, &ee) && ee.ExitCode() == 1) { // ps exits 1 when some pid is unknown
		return nil, fmt.Errorf("ps: %w", err)
	}
	res := map[int]live.Proc{}
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Fields(line)
		if len(f) < 3 {
			continue
		}
		if p, err := strconv.Atoi(f[0]); err == nil {
			res[p] = live.Proc{Start: strings.Join(f[2:], " "), Zombie: strings.HasPrefix(f[1], "Z")}
		}
	}
	return res, nil
}
