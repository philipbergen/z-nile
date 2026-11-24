package fxtree

import (
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"time"
)

// templatePatterns name the folders test binaries make in the temp folder and remove when they end: the fixture templates, the
// git template and the host fixture.
var templatePatterns = []string{"zn-*template*", "zn-host-fixture-*"}

// Freeze makes the tree at dir refuse a write, rename or delete inside it, without changing a mode bit (so a program that
// compares modes still finds it complete): folders are made 0500 and, on macOS, every entry gets the user-immutable flag. The
// tree must be released (Release) before it can be removed.
func Freeze(dir string) error {
	var dirs []string
	filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err == nil && d.IsDir() {
			dirs = append(dirs, p)
		}
		return nil
	})
	for i := len(dirs) - 1; i >= 0; i-- { // children first, so every chmod still reaches its folder
		if err := os.Chmod(dirs[i], 0o500); err != nil {
			return err
		}
	}
	return setImmutable(dir, true)
}

// Release undoes Freeze and removes the tree at dir. It never follows a link, and it ignores errors: it is cleanup.
func Release(dir string) {
	setImmutable(dir, false)
	filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if d != nil && d.IsDir() {
			os.Chmod(p, 0o700) // before the folder is read, so an unreadable one is entered
		}
		return nil
	})
	os.RemoveAll(dir)
}

// Sweep removes the fixture template folders of earlier test runs (a killed run never released its own) that sit directly in
// parent and were last changed more than olderThan ago, and returns how many it removed. A younger one is another run's and is
// left alone, as is anything that is not a plain folder (a link is never followed) or does not match a template name. It
// stops after thirty seconds.
func Sweep(parent string, olderThan time.Duration) int {
	entries, err := os.ReadDir(parent)
	if err != nil {
		return 0
	}
	deadline := time.Now().Add(30 * time.Second)
	removed := 0
	for _, e := range entries {
		if time.Now().After(deadline) {
			break
		}
		if !matchesTemplate(e.Name()) {
			continue
		}
		p := filepath.Join(parent, e.Name())
		fi, err := os.Lstat(p)
		if err != nil || !fi.IsDir() || time.Since(fi.ModTime()) <= olderThan {
			continue
		}
		Release(p)
		if _, err := os.Lstat(p); err != nil {
			removed++
		}
	}
	return removed
}

func matchesTemplate(name string) bool {
	for _, pat := range templatePatterns {
		if ok, _ := path.Match(pat, name); ok {
			return true
		}
	}
	return false
}
