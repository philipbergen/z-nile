package fxtree

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func readOnlyTree(t *testing.T, dir string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(dir, "cache", "zn", "id"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "cache", "zn", "id", "f"), []byte("x"), 0o444); err != nil {
		t.Fatal(err)
	}
	for _, d := range []string{filepath.Join(dir, "cache", "zn", "id"), filepath.Join(dir, "cache", "zn"), filepath.Join(dir, "cache"), dir} {
		if err := os.Chmod(d, 0o500); err != nil {
			t.Fatal(err)
		}
	}
}

// A killed test run leaves its read-only templates behind (TestMain's restore never ran): the next run's TestMain sweeps those
// older than an hour, and only those (c0179 design review C2).
func TestSweepRemovesAStaleReadOnlyTemplateAndKeepsAFreshOneAndOthers(t *testing.T) {
	t.Parallel()
	tmp := t.TempDir()
	stale := filepath.Join(tmp, "zn-engine-template-111")
	fresh := filepath.Join(tmp, "zn-engine-template-222")
	other := filepath.Join(tmp, "zn-not-a-fixture-333")
	oldGit := filepath.Join(tmp, "zn-gittemplate-444")
	outside := filepath.Join(tmp, "elsewhere")
	link := filepath.Join(tmp, "zn-link-template-555")
	for _, d := range []string{stale, fresh, other, oldGit, outside} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	readOnlyTree(t, stale)
	readOnlyTree(t, fresh)
	if err := os.WriteFile(filepath.Join(outside, "keep"), []byte("k"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, link); err != nil {
		t.Fatal(err)
	}
	old := time.Now().Add(-2 * time.Hour)
	for _, d := range []string{stale, other, oldGit} {
		if err := os.Chtimes(d, old, old); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Chtimes(link, old, old); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { Release(fresh) })
	n := Sweep(tmp, time.Hour)
	if _, err := os.Lstat(stale); err == nil {
		t.Error("the stale read-only template was not removed")
	}
	if _, err := os.Lstat(oldGit); err == nil {
		t.Error("the stale git template was not removed")
	}
	if _, err := os.Lstat(fresh); err != nil {
		t.Error("a template younger than an hour (another run's) was removed")
	}
	if _, err := os.Lstat(other); err != nil {
		t.Error("a folder that is not a fixture template was removed")
	}
	if _, err := os.Lstat(filepath.Join(outside, "keep")); err != nil {
		t.Error("a link was followed and its target's file removed")
	}
	if n != 2 {
		t.Errorf("Sweep reported %d removed, want 2", n)
	}
}

func TestReleaseRemovesAReadOnlyTree(t *testing.T) {
	t.Parallel()
	d := filepath.Join(t.TempDir(), "tpl")
	if err := os.MkdirAll(d, 0o755); err != nil {
		t.Fatal(err)
	}
	readOnlyTree(t, d)
	Release(d)
	if _, err := os.Lstat(d); err == nil {
		t.Error("a read-only tree was not removed")
	}
}
