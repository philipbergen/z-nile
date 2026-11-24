package lunepin

import (
	"bytes"
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
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

// L, N11: under a zip pin (no binary digest to compare) no lune on PATH is ever run, a rokit shim included (a copied
// shim starts lune by name, so itself, without end); only rokit's stored binary of exactly the pinned version, which
// must report exactly that version, is taken.
func TestFindNeverRunsARokitShim(t *testing.T) {
	dir := t.TempDir()
	shimDir := filepath.Join(dir, ".rokit", "bin")
	_, shimMarker := fakeLune(t, shimDir, "lune 0.10.5")
	onPath, pathMarker := fakeLune(t, filepath.Join(dir, "onpath"), "lune 0.10.5")
	zip := "zip " + platform() + " " + strings.Repeat("2", 64) + " lune-0.10.5-" + platform() + ".zip\n"
	home := filepath.Join(dir, "home")
	if got, ok := Find(zip, shimDir+":"+filepath.Dir(onPath), home); ok {
		t.Errorf("a lune on PATH was taken: %s", got)
	}
	if ran(shimMarker) || ran(pathMarker) {
		t.Error("a lune on PATH was run")
	}
	store := filepath.Join(home, ".rokit", "tool-storage", "lune-org", "lune")
	other, otherMarker := fakeLune(t, filepath.Join(store, "0.9.0"), "lune 0.10.5")
	if got, ok := Find(zip, "", home); ok {
		t.Errorf("another version's folder was taken: %s", got)
	}
	if ran(otherMarker) {
		t.Errorf("%s was run", other)
	}
	stored, _ := fakeLune(t, filepath.Join(store, "0.10.5"), "lune 0.10.50")
	if got, ok := Find(zip, "", home); ok {
		t.Errorf("a binary reporting 0.10.50 was taken for 0.10.5: %s", got)
	}
	os.WriteFile(stored, []byte("#!/bin/sh\necho 'lune 0.10.5'\n"), 0o755)
	if got, ok := Find(zip, "", home); !ok || got != stored {
		t.Errorf("the stored Lune was not found: %q %v", got, ok)
	}
}

// L: the probe Find runs is bounded: a candidate that never ends costs the bound, not the test.
func TestFindsProbeIsBounded(t *testing.T) {
	versionTimeout = 500 * time.Millisecond
	defer func() { versionTimeout = 10 * time.Second }()
	home := t.TempDir()
	dir := filepath.Join(home, ".rokit", "tool-storage", "lune-org", "lune", "0.10.5")
	os.MkdirAll(dir, 0o755)
	os.WriteFile(filepath.Join(dir, "lune"), []byte("#!/bin/sh\n/bin/sleep 30\necho 'lune 0.10.5'\n"), 0o755)
	start := time.Now()
	if _, ok := Find("zip "+platform()+" "+strings.Repeat("3", 64)+" lune-0.10.5-"+platform()+".zip\n", "", home); ok {
		t.Error("a candidate that never answered was taken")
	}
	if d := time.Since(start); d > 5*time.Second {
		t.Errorf("Find took %s", d)
	}
}

// N11: a program run with a lifeline dies with the process that started it, even when that process is killed outright.
func TestALifelineDiesWithItsStarter(t *testing.T) {
	pidFile := filepath.Join(t.TempDir(), "pid")
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	helper := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestLifelineHelper$")
	helper.Env = append(os.Environ(), "LUNEPIN_LIFELINE_HELPER="+pidFile)
	if err := helper.Start(); err != nil {
		t.Fatal(err)
	}
	var pid int
	for i := 0; i < 200 && pid == 0; i++ {
		if b, err := os.ReadFile(pidFile); err == nil && strings.HasSuffix(string(b), "\n") {
			pid, _ = strconv.Atoi(strings.TrimSpace(string(b)))
		} else {
			time.Sleep(25 * time.Millisecond)
		}
	}
	if pid == 0 {
		helper.Process.Kill()
		t.Fatal("the helper never started its program")
	}
	helper.Process.Kill() // the starter dies without a chance to clean up
	helper.Wait()
	for i := 0; i < 100 && syscall.Kill(pid, 0) == nil; i++ {
		time.Sleep(20 * time.Millisecond)
	}
	if syscall.Kill(pid, 0) == nil {
		syscall.Kill(pid, syscall.SIGKILL)
		t.Error("the program outlived the process that started it")
	}
}

// TestLifelineHelper is the starter TestALifelineDiesWithItsStarter kills: it runs only with the variable set.
func TestLifelineHelper(t *testing.T) {
	pidFile := os.Getenv("LUNEPIN_LIFELINE_HELPER")
	if pidFile == "" {
		t.Skip("run by TestALifelineDiesWithItsStarter")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	RunLifeline(ctx, "", nil, io.Discard, io.Discard, "/bin/sh", "-c", "echo $$ > '"+pidFile+".tmp'; mv '"+pidFile+".tmp' '"+pidFile+"'; exec /bin/sleep 30")
}

// N11: a run with a lifeline gives back the program's exit status and output.
func TestALifelineKeepsTheResult(t *testing.T) {
	var out bytes.Buffer
	err := RunLifeline(context.Background(), "", []string{"PATH=/usr/bin:/bin"}, &out, io.Discard, "/bin/sh", "-c", "echo hi; exit 3")
	var ee *exec.ExitError
	if !errors.As(err, &ee) || ee.ExitCode() != 3 || out.String() != "hi\n" {
		t.Errorf("err %v, out %q", err, out.String())
	}
	if err := RunLifeline(context.Background(), "", []string{"PATH=/usr/bin:/bin"}, io.Discard, io.Discard, "/bin/sh", "-c", "exit 0"); err != nil {
		t.Errorf("a clean exit: %v", err)
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
