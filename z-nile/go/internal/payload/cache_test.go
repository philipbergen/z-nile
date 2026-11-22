package payload

import (
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

// f0427 step 2 (AC3): the cache is verified on every run, made 0700, and refused when it is not the user's own.

// extracted lays the payload out in a fresh cache and returns the cache folder, the payload and the extracted folder.
func extracted(t *testing.T) (cache string, p Payload, dir string) {
	t.Helper()
	cache = filepath.Join(t.TempDir(), "zn")
	p = payloadOf(t)
	dir, fresh, err := Extract(cache, p)
	if err != nil || !fresh {
		t.Fatalf("extract: %v fresh=%v", err, fresh)
	}
	return cache, p, dir
}

func mustRead(t *testing.T, path string) []byte {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func stales(cache string) []string {
	m, _ := filepath.Glob(filepath.Join(cache, ".stale-*"))
	return m
}

// every way an extracted file can be changed without a symlink or a writable bit: Extract must put a good folder back.
var tampers = []struct {
	name string
	do   func(t *testing.T, dir string)
}{
	{"one byte of the lune flipped", func(t *testing.T, dir string) {
		f := filepath.Join(dir, "bin", "lune")
		b := mustRead(t, f)
		b[len(b)-2] ^= 1
		os.WriteFile(f, b, 0o700)
	}},
	{"the lune replaced by a longer decoy", func(t *testing.T, dir string) {
		os.WriteFile(filepath.Join(dir, "bin", "lune"), []byte("#!/bin/sh\ntouch decoy-ran\nexit 97\n"), 0o700)
	}},
	{"the lune truncated", func(t *testing.T, dir string) { os.Truncate(filepath.Join(dir, "bin", "lune"), 3) }},
	{"the lune deleted", func(t *testing.T, dir string) { os.Remove(filepath.Join(dir, "bin", "lune")) }},
	{"one byte of an engine file flipped (same size)", func(t *testing.T, dir string) {
		f := filepath.Join(dir, "z-nile", "engine", "main.luau")
		b := mustRead(t, f)
		b[0] ^= 1
		os.WriteFile(f, b, 0o600)
	}},
	{"an engine file truncated", func(t *testing.T, dir string) { os.Truncate(filepath.Join(dir, "z-nile", "engine", "main.luau"), 4) }},
	{"an engine file deleted", func(t *testing.T, dir string) { os.Remove(filepath.Join(dir, "z-nile", "roots.luau")) }},
	{"an engine file lost its executable bit", func(t *testing.T, dir string) { os.Chmod(filepath.Join(dir, "z-nile", "lib", "run.sh"), 0o600) }},
	{"an engine file gained the group's read bit", func(t *testing.T, dir string) { os.Chmod(filepath.Join(dir, "z-nile", "roots.luau"), 0o640) }},
	{"a file planted in the engine folder", func(t *testing.T, dir string) {
		os.WriteFile(filepath.Join(dir, "z-nile", "engine", "planted.luau"), []byte("print('x')\n"), 0o600)
	}},
	{"the marker deleted", func(t *testing.T, dir string) { os.Remove(filepath.Join(dir, Marker)) }},
	{"an engine folder deleted whole", func(t *testing.T, dir string) { os.RemoveAll(filepath.Join(dir, "z-nile", "lib")) }},
}

func TestEveryRunVerifiesTheExtractedFilesAndReextractsOnAnyChange(t *testing.T) {
	for _, c := range tampers {
		t.Run(c.name, func(t *testing.T) {
			cache, p, dir := extracted(t)
			c.do(t, dir)
			dir2, fresh, err := Extract(cache, p)
			if err != nil || !fresh || dir2 != dir {
				t.Fatalf("after %s: err=%v fresh=%v dir=%s", c.name, err, fresh, dir2)
			}
			if got := mustRead(t, filepath.Join(dir, "bin", "lune")); string(got) != string(p.Lune) {
				t.Fatalf("the lune at %s is not the embedded one", dir)
			}
			// and the folder it put back verifies, so the next run extracts nothing
			if _, fresh, err := Extract(cache, p); err != nil || fresh {
				t.Fatalf("the replacement does not verify: err=%v fresh=%v", err, fresh)
			}
		})
	}
}

// F14: a folder with a changed file may be in use by another zn, so it is never deleted: it is moved aside, young enough
// that the sweep leaves it. The mutants: RemoveAll of the target, and moving it aside with its old modified time.
func TestAReextractionNeverDeletesTheFolderItReplaces(t *testing.T) {
	cache, p, dir := extracted(t)
	live := filepath.Join(dir, "z-nile", "engine", "live.txt") // an extra file also marks the folder as changed
	os.WriteFile(live, []byte("another zn is reading this folder\n"), 0o600)
	old := time.Now().Add(-48 * time.Hour)
	os.Chtimes(dir, old, old)
	if _, fresh, err := Extract(cache, p); err != nil || !fresh {
		t.Fatalf("extract: %v fresh=%v", err, fresh)
	}
	moved := stales(cache)
	if len(moved) != 1 {
		t.Fatalf("the replaced folder is not kept aside: %v", moved)
	}
	if _, err := os.Stat(filepath.Join(moved[0], "z-nile", "engine", "live.txt")); err != nil {
		t.Fatalf("the replaced folder lost its files: %v", err)
	}
	if _, err := os.Stat(live); err == nil {
		t.Fatal("the planted file is still in the new folder")
	}
}

func TestSeveralRunsOnATamperedFolderAllEndWithAGoodOne(t *testing.T) {
	for round := 0; round < 5; round++ {
		cache, p, dir := extracted(t)
		os.WriteFile(filepath.Join(dir, "z-nile", "engine", "main.luau"), []byte("tampered\n"), 0o600)
		var wg sync.WaitGroup
		errs := make(chan error, 8)
		for i := 0; i < 8; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				d, _, err := Extract(cache, p)
				if err != nil {
					errs <- err
					return
				}
				time.Sleep(5 * time.Millisecond)
				if b, err := os.ReadFile(filepath.Join(d, "z-nile", "engine", "main.luau")); err != nil || string(b) != "print('engine')\n" {
					errs <- err
				}
			}()
		}
		wg.Wait()
		close(errs)
		for err := range errs {
			t.Fatalf("round %d: %v", round, err)
		}
		if _, fresh, err := Extract(cache, p); err != nil || fresh {
			t.Fatalf("round %d: the folder does not verify afterwards: %v fresh=%v", round, err, fresh)
		}
	}
}

func TestACacheFolderThatIsASymlinkIsRefusedAndNothingIsWrittenThroughIt(t *testing.T) {
	cache, p, dir := extracted(t)
	real := cache + "-real"
	if err := os.Rename(cache, real); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(real, cache); err != nil {
		t.Fatal(err)
	}
	_ = dir
	before, _ := os.ReadDir(real)
	_, _, err := Extract(cache, p)
	if err == nil || !strings.Contains(err.Error(), cache) || !strings.Contains(err.Error(), "symbolic link") {
		t.Fatalf("a symlinked cache folder was accepted: %v", err)
	}
	after, _ := os.ReadDir(real)
	if len(before) != len(after) {
		t.Fatalf("something was written through the link: %d -> %d entries", len(before), len(after))
	}
}

func TestALinkInsideTheCacheIsRefusedNamingIt(t *testing.T) {
	cases := []struct {
		name string
		rel  string // the path that becomes a link (relative to the extracted folder, "" for the folder itself)
	}{
		{"the extracted folder", ""},
		{"bin", "bin"},
		{"the lune", "bin/lune"},
		{"an engine folder", "z-nile/engine"},
		{"an engine file", "z-nile/roots.luau"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			cache, p, dir := extracted(t)
			target := filepath.Join(dir, c.rel)
			elsewhere := filepath.Join(t.TempDir(), "elsewhere")
			if err := os.Rename(target, elsewhere); err != nil {
				t.Fatal(err)
			}
			if err := os.Symlink(elsewhere, target); err != nil {
				t.Fatal(err)
			}
			_, _, err := Extract(cache, p)
			if err == nil || !strings.Contains(err.Error(), target) || !strings.Contains(err.Error(), "symbolic link") {
				t.Fatalf("a link at %s: %v", target, err)
			}
		})
	}
}

func TestAFolderOrRuntimeFileWritableByGroupOrOthersIsRefusedNamingIt(t *testing.T) {
	for _, mode := range []os.FileMode{0o770, 0o707, 0o777, 0o720, 0o702} {
		for _, rel := range []string{"", "bin", "bin/lune", "z-nile/engine", "z-nile/engine/main.luau"} {
			cache, p, dir := extracted(t)
			target := filepath.Join(dir, rel)
			if err := os.Chmod(target, mode); err != nil {
				t.Fatal(err)
			}
			_, _, err := Extract(cache, p)
			if err == nil || !strings.Contains(err.Error(), target) || !strings.Contains(err.Error(), "writable") {
				t.Fatalf("%s at %v: %v", target, mode, err)
			}
		}
	}
	// the cache folder itself
	cache, p, _ := extracted(t)
	if err := os.Chmod(cache, 0o777); err != nil {
		t.Fatal(err)
	}
	if _, _, err := Extract(cache, p); err == nil || !strings.Contains(err.Error(), cache) || !strings.Contains(err.Error(), "writable") {
		t.Fatalf("a world-writable cache folder: %v", err)
	}
}

func TestAFolderOthersCanOnlyReadIsNotRefused(t *testing.T) {
	cache, p, dir := extracted(t)
	os.Chmod(cache, 0o755)
	os.Chmod(filepath.Join(dir, "bin"), 0o750)
	if _, _, err := Extract(cache, p); err != nil {
		t.Fatalf("a read-only-for-others folder was refused: %v", err)
	}
}

// swapOwner makes ownerOf report another user for exactly the paths named, and the current user for the rest.
func swapOwner(t *testing.T, paths ...string) {
	t.Helper()
	oldOwner := ownerOf
	t.Cleanup(func() { ownerOf = oldOwner })
	var infos []os.FileInfo
	for _, p := range paths {
		fi, err := os.Lstat(p)
		if err != nil {
			t.Fatal(err)
		}
		infos = append(infos, fi)
	}
	ownerOf = func(fi os.FileInfo) (int, bool) {
		for _, x := range infos {
			if os.SameFile(fi, x) {
				return currentUID() + 1, true
			}
		}
		return oldOwner(fi)
	}
}

func TestAFolderOrRuntimeFileOwnedByAnotherUserIsRefusedNamingIt(t *testing.T) {
	for _, rel := range []string{"", "bin", "bin/lune", "z-nile/engine", "z-nile/engine/main.luau"} {
		cache, p, dir := extracted(t)
		target := filepath.Join(dir, rel)
		swapOwner(t, target)
		_, _, err := Extract(cache, p)
		if err == nil || !strings.Contains(err.Error(), target) || !strings.Contains(err.Error(), "owned by") {
			t.Fatalf("%s owned by another user: %v", target, err)
		}
	}
	cache, p, _ := extracted(t)
	swapOwner(t, cache)
	if _, _, err := Extract(cache, p); err == nil || !strings.Contains(err.Error(), cache) || !strings.Contains(err.Error(), "owned by") {
		t.Fatalf("a cache folder owned by another user: %v", err)
	}
}

func TestEveryFolderAndFileIsCreatedPrivate(t *testing.T) {
	old := syscall.Umask(0) // a umask must not be what makes the folders private
	defer syscall.Umask(old)
	root := t.TempDir()
	cache := filepath.Join(root, "new", "base", "zn") // none of the parents exist
	p := payloadOf(t)
	dir, _, err := Extract(cache, p)
	if err != nil {
		t.Fatal(err)
	}
	for _, d := range []string{filepath.Join(root, "new"), filepath.Join(root, "new", "base"), cache} {
		if st, err := os.Stat(d); err != nil || st.Mode().Perm() != 0o700 {
			t.Errorf("%s: %v %v, want drwx------", d, st.Mode(), err)
		}
	}
	filepath.WalkDir(dir, func(path string, e os.DirEntry, err error) error {
		fi, _ := e.Info()
		if e.IsDir() && fi.Mode().Perm() != 0o700 {
			t.Errorf("folder %s is %v, want 0700", path, fi.Mode().Perm())
		}
		if !e.IsDir() && fi.Mode().Perm()&0o077 != 0 {
			t.Errorf("file %s is %v: group or others can use it", path, fi.Mode().Perm())
		}
		return nil
	})
	// a failed or cleaned up temporary folder is private too: the one in use while laying out
	seen := os.FileMode(0)
	afterLay = func(tmp string) { st, _ := os.Stat(tmp); seen = st.Mode().Perm() }
	defer func() { afterLay = nil }()
	if _, _, err := Extract(filepath.Join(root, "second", "zn"), payloadOf(t)); err != nil {
		t.Fatal(err)
	}
	if seen != 0o700 {
		t.Errorf("the temporary folder was %v", seen)
	}
}

func TestACacheNamedByXDGIsUsedOnlyWhenAbsoluteAndOwned(t *testing.T) {
	home := t.TempDir()
	xdg := t.TempDir()
	file := filepath.Join(t.TempDir(), "a-file")
	os.WriteFile(file, nil, 0o600)
	cases := []struct {
		name string
		env  []string
		want string
	}{
		{"absolute and owned", []string{"XDG_CACHE_HOME=" + xdg, "HOME=" + home}, filepath.Join(xdg, "zn")},
		{"relative", []string{"XDG_CACHE_HOME=relative/dir", "HOME=" + home}, filepath.Join(home, ".cache", "zn")},
		{"dot", []string{"XDG_CACHE_HOME=.", "HOME=" + home}, filepath.Join(home, ".cache", "zn")},
		{"missing", []string{"XDG_CACHE_HOME=" + filepath.Join(xdg, "nope"), "HOME=" + home}, filepath.Join(home, ".cache", "zn")},
		{"not a folder", []string{"XDG_CACHE_HOME=" + file, "HOME=" + home}, filepath.Join(home, ".cache", "zn")},
		{"empty", []string{"XDG_CACHE_HOME=", "HOME=" + home}, filepath.Join(home, ".cache", "zn")},
		{"ZN_CACHE wins", []string{"ZN_CACHE=/z", "XDG_CACHE_HOME=" + xdg, "HOME=" + home}, "/z/zn"},
	}
	for _, c := range cases {
		got, err := CacheFolder(c.env)
		if err != nil || got != c.want {
			t.Errorf("%s: %q %v, want %q", c.name, got, err, c.want)
		}
	}
	// owned by another user: ignored
	swapOwner(t, xdg)
	got, err := CacheFolder([]string{"XDG_CACHE_HOME=" + xdg, "HOME=" + home})
	if err != nil || got != filepath.Join(home, ".cache", "zn") {
		t.Errorf("XDG_CACHE_HOME owned by another user: %q %v", got, err)
	}
}

func TestACacheFolderThatCannotBeChosenSaysWhy(t *testing.T) {
	cases := []struct {
		env  []string
		want []string // every part must be in the message
	}{
		{[]string{"ZN_CACHE=relative", "HOME=/h"}, []string{"ZN_CACHE", "relative", "absolute"}},
		{[]string{}, []string{"HOME", "not set", "ZN_CACHE"}},
		{[]string{"HOME="}, []string{"HOME", "not set", "ZN_CACHE"}},
		{[]string{"HOME=rel/home"}, []string{"HOME", "rel/home", "absolute", "ZN_CACHE"}},
		{[]string{"XDG_CACHE_HOME=rel"}, []string{"HOME", "not set", "ZN_CACHE"}},
	}
	for _, c := range cases {
		got, err := CacheFolder(c.env)
		if err == nil {
			t.Errorf("%v: got %q, want a refusal", c.env, got)
			continue
		}
		for _, w := range c.want {
			if !strings.Contains(err.Error(), w) {
				t.Errorf("%v: %q lacks %q", c.env, err, w)
			}
		}
	}
}

// The lesson "a rule over paths does not bind the file": a runtime file with another hard link is the same file under a
// second name, so whoever holds the other name can change it. It is refused, naming the file.
func TestAFileWithAnotherHardLinkIsRefusedNamingIt(t *testing.T) {
	for _, rel := range []string{"bin/lune", "z-nile/engine/main.luau"} {
		cache, p, dir := extracted(t)
		target := filepath.Join(dir, rel)
		if err := os.Link(target, filepath.Join(t.TempDir(), "elsewhere")); err != nil {
			t.Fatal(err)
		}
		_, _, err := Extract(cache, p)
		if err == nil || !strings.Contains(err.Error(), target) || !strings.Contains(err.Error(), "hard link") {
			t.Fatalf("%s with a second name: %v", target, err)
		}
	}
}

// The file that was vetted is the file that is hashed: a path swapped for another file of the same bytes between the
// check and the open is caught, because the opened handle is compared with what was checked.
func TestAFileSwappedBetweenTheCheckAndTheOpenIsNotTrusted(t *testing.T) {
	cache, p, dir := extracted(t)
	target := filepath.Join(dir, "bin", "lune")
	beforeOpen = func(path string) {
		if path != target {
			return
		}
		same := mustRead(t, path)
		os.WriteFile(path+".new", same, 0o700) // the same bytes in another file, made while the old one still exists
		os.Rename(path+".new", path)
	}
	defer func() { beforeOpen = nil }()
	laid := false // a folder that failed the comparison is replaced: the temporary folder gets laid out
	afterLay = func(string) { laid = true }
	defer func() { afterLay = nil }()
	if _, _, err := Extract(cache, p); err != nil || !laid {
		t.Fatalf("a swapped file was trusted: err=%v, replacement laid out: %v", err, laid)
	}
}
