package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The cache the real-engine tests share has folders nobody can write into, so a test that tries to create, rename or delete
// there fails in that test (c0179 code review F4), and not in another test whose zn replaces what it finds changed.
func TestSharedEngineCacheFoldersAreNotWritable(t *testing.T) {
	t.Parallel()
	realEngine(t, newFake(t, false)) // builds the template (and skips where there is no pinned Lune)
	cache := filepath.Join(engineTemplate.dir, "cache")
	dirs := 0
	err := filepath.WalkDir(cache, func(p string, d fs.DirEntry, err error) error {
		if err == nil && d.IsDir() {
			dirs++
			if info, err := d.Info(); err != nil || info.Mode().Perm()&0o222 != 0 {
				t.Errorf("%s is writable (%v, %v)", p, info.Mode(), err)
			}
		}
		return err
	})
	if err != nil || dirs < 5 {
		t.Fatalf("walked %d folders: %v", dirs, err)
	}
	if f, err := os.Create(filepath.Join(cache, "zn", "intruder")); err == nil {
		f.Close()
		os.Remove(filepath.Join(cache, "zn", "intruder"))
		t.Error("a file could be created in the shared cache")
	}
}

// One real-engine test starts from an empty cache of its own: zn extracts the payload through the product, and then runs the
// real engine from it. The shared cache means no other real-engine test does (c0179 code review F4).
func TestAnEmptyCacheIsExtractedByZnAndTheRealEngineRuns(t *testing.T) {
	t.Parallel()
	f := newFake(t, false)
	cache := filepath.Join(resolved(t), "cache")
	eng := realEngineIn(t, f, cache)
	dir := resolved(t)
	f.d.cwd = func() (string, error) { return dir, nil }
	run([]string{"--help"}, f.d) // the engine prints its usage and exits 1: what shows it ran is its text
	if !strings.HasPrefix(f.out.String(), "usage: ./zn <command>") {
		t.Fatalf("the real engine did not print its usage (engine exit %d): %s / %s", eng.code, f.errOut.String(), f.out.String())
	}
	luns, _ := filepath.Glob(filepath.Join(cache, "zn", "*", "bin", "lune"))
	if len(luns) != 1 {
		t.Fatalf("zn extracted no payload into the empty cache: %v", luns)
	}
}
