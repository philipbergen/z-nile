package lunepin

import (
	"context"
	"crypto/sha256"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"
)

// fakeLune writes an executable "lune" in dir that leaves a marker file when it runs and prints what it is told.
func fakeLune(t *testing.T, dir, prints string) (path, marker string) {
	t.Helper()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	marker = filepath.Join(t.TempDir(), "ran")
	path = filepath.Join(dir, "lune")
	body := "#!/bin/sh\n: > '" + marker + "'\necho '" + prints + "'\n"
	if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	return path, marker
}

func digest(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return fmt.Sprintf("%x", sha256.Sum256(b))
}

func platform() string {
	p := runtime.GOOS + "-" + map[string]string{"arm64": "aarch64", "amd64": "x86_64"}[runtime.GOARCH]
	if p != Platform() {
		panic("Platform() is " + Platform() + ", want " + p)
	}
	return p
}

func ran(marker string) bool { _, err := os.Stat(marker); return err == nil }

// L: a binary pin accepts only the pinned bytes, and never runs a candidate to decide.
func TestFindTakesOnlyThePinnedBinaryAndRunsNothing(t *testing.T) {
	dir := t.TempDir()
	p, marker := fakeLune(t, filepath.Join(dir, "bin"), "lune 0.10.5")
	other := "bin " + platform() + " " + strings.Repeat("0", 64) + " lune\n"
	if got, ok := Find(other, filepath.Join(dir, "bin"), dir); ok {
		t.Errorf("a Lune with another digest was taken: %s", got)
	}
	pinned := "# a comment\nzip some-other-platform " + strings.Repeat("1", 64) + " x.zip\nbin " + platform() + " " + digest(t, p) + " lune\n"
	if got, ok := Find(pinned, filepath.Join(dir, "bin"), dir); !ok || got != p {
		t.Errorf("the pinned Lune was not found: %q %v", got, ok)
	}
	if ran(marker) {
		t.Error("Find ran a candidate under a binary pin")
	}
	if got, ok := Find("", filepath.Join(dir, "bin"), dir); ok {
		t.Errorf("no pin for this platform, yet %s was taken", got)
	}
}

// L: under a zip pin, a rokit shim is never run (a copied shim starts lune by name, so itself, without end); a binary
// that reports the pinned version with an empty PATH is taken.
func TestFindNeverRunsARokitShim(t *testing.T) {
	dir := t.TempDir()
	shimDir := filepath.Join(dir, ".rokit", "bin")
	_, shimMarker := fakeLune(t, shimDir, "lune 0.10.5")
	zip := "zip " + platform() + " " + strings.Repeat("2", 64) + " lune-0.10.5-" + platform() + ".zip\n"
	if got, ok := Find(zip, shimDir, filepath.Join(dir, "nohome")); ok {
		t.Errorf("a shim was taken: %s", got)
	}
	if ran(shimMarker) {
		t.Error("a rokit shim was run")
	}
	real, _ := fakeLune(t, filepath.Join(dir, "real"), "lune 0.10.5")
	if got, ok := Find(zip, shimDir+":"+filepath.Join(dir, "real"), filepath.Join(dir, "nohome")); !ok || got != real {
		t.Errorf("the real Lune was not found: %q %v", got, ok)
	}
	wrong, _ := fakeLune(t, filepath.Join(dir, "wrong"), "lune 0.9.0")
	if got, ok := Find(zip, filepath.Dir(wrong), filepath.Join(dir, "nohome")); ok {
		t.Errorf("another version was taken: %s", got)
	}
}

// L: the probe Find runs is bounded: a candidate that never ends costs the bound, not the test.
func TestFindsProbeIsBounded(t *testing.T) {
	versionTimeout = 500 * time.Millisecond
	defer func() { versionTimeout = 10 * time.Second }()
	dir := filepath.Join(t.TempDir(), "slow")
	os.MkdirAll(dir, 0o755)
	os.WriteFile(filepath.Join(dir, "lune"), []byte("#!/bin/sh\n/bin/sleep 30\necho 'lune 0.10.5'\n"), 0o755)
	start := time.Now()
	if _, ok := Find("zip "+platform()+" "+strings.Repeat("3", 64)+" lune-0.10.5-"+platform()+".zip\n", dir, t.TempDir()); ok {
		t.Error("a candidate that never answered was taken")
	}
	if d := time.Since(start); d > 5*time.Second {
		t.Errorf("Find took %s", d)
	}
}

// L: a bounded command is stopped at its deadline with everything it started, its children included.
func TestCommandStopsTheWholeGroup(t *testing.T) {
	pidFile := filepath.Join(t.TempDir(), "child")
	ctx, cancel := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancel()
	cmd := Command(ctx, "/bin/sh", "-c", "sleep 30 & echo $! > '"+pidFile+"'; wait")
	start := time.Now()
	if err := cmd.Run(); err == nil {
		t.Error("a command past its deadline succeeded")
	}
	if d := time.Since(start); d > 5*time.Second {
		t.Errorf("the command ran %s past a 0.5 s deadline", d)
	}
	b, err := os.ReadFile(pidFile)
	if err != nil {
		t.Fatal(err)
	}
	pid, _ := strconv.Atoi(strings.TrimSpace(string(b)))
	for i := 0; i < 50 && syscall.Kill(pid, 0) == nil; i++ {
		time.Sleep(20 * time.Millisecond)
	}
	if syscall.Kill(pid, 0) == nil {
		syscall.Kill(pid, syscall.SIGKILL)
		t.Error("the command's child outlived it")
	}
}
