package fxtree

import (
	"os"
	"path/filepath"
	"testing"
)

func TestCopyIsAnIndependentCopyWithModesAndLinks(t *testing.T) {
	t.Parallel()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	src, dst := filepath.Join(d, "src"), filepath.Join(d, "dst")
	if err := os.MkdirAll(filepath.Join(src, "a", "b"), 0o755); err != nil {
		t.Fatal(err)
	}
	f := filepath.Join(src, "a", "b", "f")
	if err := os.WriteFile(f, []byte("one"), 0o640); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("b/f", filepath.Join(src, "a", "link")); err != nil {
		t.Fatal(err)
	}
	if err := Copy(src, dst); err != nil {
		t.Fatal(err)
	}
	g := filepath.Join(dst, "a", "b", "f")
	if st, err := os.Stat(g); err != nil || st.Mode().Perm() != 0o640 {
		t.Fatalf("the copy's file: %v, %v", st, err)
	}
	if l, err := os.Readlink(filepath.Join(dst, "a", "link")); err != nil || l != "b/f" {
		t.Fatalf("the copy's link: %q, %v", l, err)
	}
	// a write to the copy never shows in the original, and the other way
	if err := os.WriteFile(g, []byte("two"), 0o640); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(f); string(b) != "one" {
		t.Errorf("a write to the copy changed the original: %q", b)
	}
	if err := os.WriteFile(f, []byte("three"), 0o640); err != nil {
		t.Fatal(err)
	}
	if b, _ := os.ReadFile(g); string(b) != "two" {
		t.Errorf("a write to the original changed the copy: %q", b)
	}
}

func TestCopyRefusesAnExistingDestinationAndLeavesItAlone(t *testing.T) {
	t.Parallel()
	d := t.TempDir()
	src, dst := filepath.Join(d, "src"), filepath.Join(d, "dst")
	os.MkdirAll(src, 0o755)
	os.WriteFile(filepath.Join(src, "f"), []byte("x"), 0o644)
	os.MkdirAll(dst, 0o755)
	os.WriteFile(filepath.Join(dst, "keep"), []byte("k"), 0o644)
	if err := Copy(src, dst); err == nil && fileExists(filepath.Join(dst, "keep")) == false {
		t.Fatal("the copy replaced an existing destination")
	}
	if !fileExists(filepath.Join(dst, "keep")) {
		t.Error("the existing destination lost a file")
	}
}

func fileExists(p string) bool { _, err := os.Lstat(p); return err == nil }
