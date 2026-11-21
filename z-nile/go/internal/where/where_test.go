package where_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

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
