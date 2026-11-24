// Package lunepin finds the Lune that zn pins (cmd/zn/lune.sum) for the tests that run the real engine, and starts a
// program bounded: in a process group of its own that is killed whole at its deadline (f0428 step 4, item L: a rokit
// shim copied as the Lune once started about 1,700 Lune processes, each starting the next).
package lunepin

import (
	"bytes"
	"context"
	"crypto/sha256"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
	"syscall"
	"time"
)

// versionTimeout bounds the one probe Find may run (a test lowers it).
var versionTimeout = 10 * time.Second

// zipVersion is the Lune version a zip pin's file name carries (lune-0.10.5-linux-x86_64.zip).
var zipVersion = regexp.MustCompile(`^lune-(\d+\.\d+\.\d+)-`)

// Platform is this machine's platform as lune.sum names it (darwin-aarch64, linux-x86_64).
func Platform() string {
	return runtime.GOOS + "-" + map[string]string{"arm64": "aarch64", "amd64": "x86_64"}[runtime.GOARCH]
}

// pin is this platform's line of lune.sum: its kind (bin or zip), its sha256 and its file name.
func pin(sum string) (kind, digest, name string) {
	for _, line := range strings.Split(sum, "\n") {
		if f := strings.Fields(line); len(f) == 4 && !strings.HasPrefix(line, "#") && f[1] == Platform() {
			kind, digest, name = f[0], f[2], f[3]
		}
	}
	return kind, digest, name
}

// Find is the Lune binary that sum (the text of lune.sum) pins for this platform. Under a binary pin it is the first
// file on pathList (a PATH value), then in rokit's tool storage under home, whose sha256 is the pinned one; nothing is
// run to decide, and a folder of rokit shims is never looked in (a shim started from elsewhere starts "lune" by name
// again, so itself, without end). Under a zip pin (no binary digest to compare) nothing on PATH is run at all: only
// rokit's stored binary of exactly the version the zip's name carries counts, and only when, run bounded with a PATH
// that holds no Lune, it reports exactly that version.
func Find(sum, pathList, home string) (string, bool) {
	kind, digest, name := pin(sum)
	stored := filepath.Join(home, ".rokit", "tool-storage", "lune-org", "lune")
	switch kind {
	case "bin":
		var cands []string
		for _, d := range strings.Split(pathList, ":") {
			if d != "" && !strings.Contains(d+"/", "/.rokit/") {
				cands = append(cands, filepath.Join(d, "lune"))
			}
		}
		more, _ := filepath.Glob(filepath.Join(stored, "*", "lune"))
		for _, p := range append(cands, more...) {
			if !executable(p) {
				continue
			}
			if b, err := os.ReadFile(p); err == nil && fmt.Sprintf("%x", sha256.Sum256(b)) == digest {
				return p, true
			}
		}
	case "zip":
		m := zipVersion.FindStringSubmatch(name)
		if m == nil {
			return "", false
		}
		p := filepath.Join(stored, m[1], "lune")
		if !executable(p) {
			return "", false
		}
		ctx, cancel := context.WithTimeout(context.Background(), versionTimeout)
		defer cancel()
		cmd := Command(ctx, p, "--version")
		cmd.Env = []string{"PATH=" + filepath.Join(os.TempDir(), "no-lune-here")}
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err == nil && strings.TrimSpace(out.String()) == "lune "+m[1] {
			return p, true
		}
	}
	return "", false
}

func executable(p string) bool {
	st, err := os.Stat(p)
	return err == nil && st.Mode().IsRegular() && st.Mode()&0o111 != 0
}

// Command is name with args in a process group of its own, killed whole (its children included) when ctx ends, and
// never waited on for more than a second after that.
func Command(ctx context.Context, name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL) }
	cmd.WaitDelay = time.Second
	return cmd
}

// lifelineScript runs "$@" and, beside it, waits on fd 3: a pipe whose only write end the starting process holds. When
// that process ends, however it ends (SIGKILL included), the pipe closes and the whole process group (the program and
// everything it started) is killed. When the program ends first, the watcher is stopped and its status is returned.
const lifelineScript = `exec 3<&0
"$@" </dev/null 3<&- &
c=$!
{ read -r _ <&3; kill -9 0; } &
w=$!
wait "$c"
s=$?
kill "$w" 2>/dev/null
exit "$s"`

// RunLifeline runs name with args in dir and env, bounded by ctx, in a process group of its own that dies with the
// calling process: zn's registry read never outlives zn, even when zn is killed outright.
func RunLifeline(ctx context.Context, dir string, env []string, stdout, stderr io.Writer, name string, args ...string) error {
	r, w, err := os.Pipe()
	if err != nil {
		return err
	}
	defer w.Close()
	cmd := Command(ctx, "/bin/sh", append([]string{"-c", lifelineScript, "lifeline", name}, args...)...)
	cmd.Dir, cmd.Env, cmd.Stdin, cmd.Stdout, cmd.Stderr = dir, env, r, stdout, stderr
	err = cmd.Start()
	r.Close() // the child holds the read end; zn keeps only the write end, the lifeline itself
	if err != nil {
		return err
	}
	return cmd.Wait()
}
