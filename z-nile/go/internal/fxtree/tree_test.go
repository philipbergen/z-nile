package fxtree

import (
	"os"
	"path/filepath"
	"testing"
)

func makeTree(t *testing.T) (src, dst, file string) {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	src, dst = filepath.Join(d, "src"), filepath.Join(d, "dst")
	if err := os.MkdirAll(filepath.Join(src, "a", "b"), 0o755); err != nil {
		t.Fatal(err)
	}
	file = filepath.Join(src, "a", "b", "f")
	if err := os.WriteFile(file, []byte("one"), 0o640); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("b/f", filepath.Join(src, "a", "link")); err != nil {
		t.Fatal(err)
	}
	return src, dst, file
}

// checkIndependentCopy asserts dst is a copy of the tree makeTree made, with its mode and link, and independent of it.
func checkIndependentCopy(t *testing.T, dst, file string) {
	t.Helper()
	g := filepath.Join(dst, "a", "b", "f")
	if st, err := os.Stat(g); err != nil || st.Mode().Perm() != 0o640 {
		t.Fatalf("the copy's file: %v, %v", st, err)
	}
	if l, err := os.Readlink(filepath.Join(dst, "a", "link")); err != nil || l != "b/f" {
		t.Fatalf("the copy's link: %q, %v", l, err)
	}
	if err := os.WriteFile(g, []byte("two"), 0o640); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(file); string(b) != "one" {
		t.Errorf("a write to the copy changed the original: %q", b)
	}
	if err := os.WriteFile(file, []byte("three"), 0o640); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(g); string(b) != "two" {
		t.Errorf("a write to the original changed the copy: %q", b)
	}
}

func TestCopyIsAnIndependentCopyWithModesAndLinks(t *testing.T) {
	t.Parallel()
	src, dst, file := makeTree(t)
	if err := Copy(src, dst); err != nil {
		t.Fatal(err)
	}
	checkIndependentCopy(t, dst, file)
}

// The cp fallback (the only path off macOS) is tested here on every system: it must give the same independent copy.
func TestCopyFallbackIsAnIndependentCopyWithModesAndLinks(t *testing.T) {
	t.Parallel()
	src, dst, file := makeTree(t)
	if err := copyWith(src, dst, func(string, string) error { return errNoClone }); err != nil {
		t.Fatal(err)
	}
	checkIndependentCopy(t, dst, file)
}

func TestCopyRefusesAnExistingDestinationAndLeavesItAlone(t *testing.T) {
	t.Parallel()
	src, dst, _ := makeTree(t)
	if err := os.MkdirAll(dst, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dst, "keep"), []byte("k"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Copy(src, dst); err == nil {
		t.Fatal("Copy into an existing destination returned nil")
	}
	if _, err := os.Lstat(filepath.Join(dst, "src")); err == nil {
		t.Error("the tree was nested inside the existing destination")
	}
	if _, err := os.Lstat(filepath.Join(dst, "keep")); err != nil {
		t.Error("the existing destination lost a file")
	}
}
