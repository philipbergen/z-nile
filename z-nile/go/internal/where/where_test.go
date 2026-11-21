package where_test

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"znile/internal/where"
)

func write(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestMainCheckoutFromWorktreeAndSentinel(t *testing.T) {
	root := t.TempDir()
	main := filepath.Join(root, "main")
	if err := os.MkdirAll(filepath.Join(main, ".git", "worktrees", "w"), 0o755); err != nil {
		t.Fatal(err)
	}
	write(t, filepath.Join(main, ".git", "worktrees", "w", "commondir"), "../..\n")
	wt := filepath.Join(main, ".worktree", "w")
	write(t, filepath.Join(wt, ".git"), "gitdir: "+filepath.Join(main, ".git", "worktrees", "w")+"\n")
	if err := os.MkdirAll(filepath.Join(wt, "z-nile", "go"), 0o755); err != nil {
		t.Fatal(err)
	}
	for _, from := range []string{main, wt, filepath.Join(wt, "z-nile", "go")} {
		got, err := where.StateDir("", "", from)
		if err != nil || got != filepath.Join(main, ".cache", "live") {
			t.Fatalf("from %s: %q, %v", from, got, err)
		}
	}
	fenced := filepath.Join(root, "fenced")
	write(t, filepath.Join(fenced, ".git"), "gitdir: /nonexistent/pickman-fence\n")
	if _, err := where.StateDir("", "", fenced); err == nil {
		t.Fatal("the fence's sentinel led to a checkout")
	}
	if got, _ := where.StateDir("", "/x/state", fenced); got != "/x/state" {
		t.Fatalf("env: %q", got)
	}
	if got, _ := where.StateDir("/y/state", "/x/state", fenced); got != "/y/state" {
		t.Fatalf("flag: %q", got)
	}
}

// AC12 (path part): the socket stays within sun_path for any state directory.
func TestSocketPathShort(t *testing.T) {
	long := "/" + strings.Repeat("d", 200)
	if p := where.SocketPath(long); len(p) > 103 || filepath.Dir(p) != "/tmp" && len(p) > 100 {
		t.Fatalf("%d bytes: %s", len(p), p)
	}
	if a, b := where.SocketPath("/a"), where.SocketPath("/b"); a == b {
		t.Fatal("two directories share a socket")
	}
}

// F9 (AC4): permission denied is not death; pid 1 belongs to another user (or to us, as root) and lives.
func TestEPERMCountsAsAlive(t *testing.T) {
	if !(where.OSProbe{}).Alive(1) {
		t.Fatal("pid 1 counted as dead")
	}
	if !(where.OSProbe{}).Alive(os.Getpid()) {
		t.Fatal("our own pid counted as dead")
	}
}

func TestProcsStartAndUnknown(t *testing.T) {
	free := 0
	for pid := 99000; pid > 2 && free == 0; pid-- {
		if !(where.OSProbe{}).Alive(pid) {
			free = pid
		}
	}
	m, err := (where.OSProbe{}).Procs([]int{os.Getpid(), free})
	if err != nil {
		t.Fatal(err)
	}
	if p := m[os.Getpid()]; p.Start == "" || p.Zombie {
		t.Fatalf("own process: %+v", p)
	}
	if _, ok := m[free]; ok {
		t.Fatal("an unknown pid was reported")
	}
}

// F9 (AC12): an existing state directory with a looser mode is chmodded to 0700.
func TestPrepareChmodsLooseDir(t *testing.T) {
	d := filepath.Join(t.TempDir(), "state")
	if err := os.Mkdir(d, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := where.Prepare(d); err != nil {
		t.Fatal(err)
	}
	if st, _ := os.Stat(d); st.Mode().Perm() != 0o700 {
		t.Fatalf("mode %v", st.Mode().Perm())
	}
}

// F9 (AC12): the /tmp fallback is for a long TMPDIR, not a long state directory.
func TestSocketFallsBackToTmpForLongTMPDIR(t *testing.T) {
	t.Setenv("TMPDIR", "/"+strings.Repeat("t", 110))
	if p := where.SocketPath("/some/state"); filepath.Dir(p) != "/tmp" {
		t.Fatalf("%s", p)
	}
	t.Setenv("TMPDIR", "/short")
	if p := where.SocketPath("/" + strings.Repeat("d", 300)); filepath.Dir(p) != "/short" {
		t.Fatalf("a long state directory moved the socket: %s", p)
	}
}

// The macOS kernel table agrees with ps about a live process and a zombie.
func TestProcsKernelTableAgreesWithPs(t *testing.T) {
	if runtime.GOOS != "darwin" {
		t.Skip("macOS only")
	}
	me := os.Getpid()
	got, err := where.OSProbe{}.Procs([]int{me, 1999999})
	if err != nil {
		t.Fatal(err)
	}
	p, ok := got[me]
	if !ok || p.Zombie {
		t.Fatalf("own process: %+v %v", p, ok)
	}
	if _, ok := got[1999999]; ok {
		t.Fatal("a pid that does not exist was found")
	}
	out, err := exec.Command("ps", "-o", "lstart=", "-p", fmt.Sprint(me)).Output()
	if err != nil {
		t.Skipf("ps: %v", err)
	}
	psStart, err := time.ParseInLocation("Mon Jan _2 15:04:05 2006", strings.TrimSpace(string(out)), time.Local)
	if err != nil {
		t.Fatal(err)
	}
	sec, _, _ := strings.Cut(p.Start, ".")
	var s int64
	fmt.Sscan(sec, &s)
	if d := s - psStart.Unix(); d < -1 || d > 1 {
		t.Fatalf("start %s vs ps %s", p.Start, psStart)
	}
	// a child that ended and was not reaped is a zombie
	c := exec.Command("true")
	if err := c.Start(); err != nil {
		t.Fatal(err)
	}
	defer c.Wait()
	var z bool
	for i := 0; i < 100 && !z; i++ {
		time.Sleep(10 * time.Millisecond)
		m, err := where.OSProbe{}.Procs([]int{c.Process.Pid})
		z = err == nil && m[c.Process.Pid].Zombie
	}
	if !z {
		t.Fatal("an ended, unreaped child is not a zombie")
	}
}
