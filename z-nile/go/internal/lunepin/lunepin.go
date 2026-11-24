// Package lunepin finds the Lune that zn pins (cmd/zn/lune.sum) for the tests that run the real engine, and starts a
// program bounded: in a process group of its own that is killed whole at its deadline (f0428 step 4, item L: a rokit
// shim copied as the Lune once started about 1,700 Lune processes, each starting the next).
package lunepin

import (
	"bytes"
	"context"
	"crypto/sha256"
	"fmt"
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

// Find is the Lune binary that sum (the text of lune.sum) pins for this platform, looked for in each folder of
// pathList (a PATH value) and then in rokit's tool storage under home. A folder of rokit shims is never looked in: a
// shim started from elsewhere starts "lune" by name again, so itself, without end. Under a binary pin a candidate counts
// only when its sha256 is the pinned one, and nothing is run. Under a zip pin (no binary digest to compare) it counts
// when, run bounded with a PATH that holds no Lune, it reports the version the zip's name carries.
func Find(sum, pathList, home string) (string, bool) {
	kind, digest, name := pin(sum)
	var version string
	if m := zipVersion.FindStringSubmatch(name); m != nil {
		version = m[1]
	}
	if kind != "bin" && (kind != "zip" || version == "") {
		return "", false
	}
	var cands []string
	for _, d := range strings.Split(pathList, ":") {
		if d != "" && !strings.Contains(d+"/", "/.rokit/") {
			cands = append(cands, filepath.Join(d, "lune"))
		}
	}
	stored, _ := filepath.Glob(filepath.Join(home, ".rokit", "tool-storage", "lune-org", "lune", "*", "lune"))
	for _, p := range append(cands, stored...) {
		st, err := os.Stat(p)
		if err != nil || !st.Mode().IsRegular() || st.Mode()&0o111 == 0 {
			continue
		}
		if kind == "bin" {
			if b, err := os.ReadFile(p); err == nil && fmt.Sprintf("%x", sha256.Sum256(b)) == digest {
				return p, true
			}
			continue
		}
		ctx, cancel := context.WithTimeout(context.Background(), versionTimeout)
		cmd := Command(ctx, p, "--version")
		cmd.Env = []string{"PATH=" + filepath.Join(os.TempDir(), "no-lune-here")}
		var out bytes.Buffer
		cmd.Stdout = &out
		err = cmd.Run()
		cancel()
		if err == nil && strings.Contains(out.String(), version) {
			return p, true
		}
	}
	return "", false
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
