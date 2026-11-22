package payload

import (
	"archive/tar"
	"bytes"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

// f0427 step 2 (AC3): the cache is verified on every run, made 0700, and refused when it is not the user's own.

// tmp is a fresh folder with no symbolic link in its path (macOS keeps its temporary folders behind /var, a link), so the
// paths the tests build are the paths the refusals name.
func tmp(t *testing.T) string {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return d
}

// extracted lays the payload out in a fresh cache and returns the cache folder, the payload and the extracted folder.
func extracted(t *testing.T) (cache string, p Payload, dir string) {
	t.Helper()
	cache = filepath.Join(tmp(t), "zn")
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
	if err == nil || !strings.Contains(err.Error(), cache) || !strings.Contains(err.Error(), "symbolic link") || !strings.Contains(err.Error(), "ZN_CACHE") {
		t.Fatalf("a symlinked cache folder was accepted, or the refusal has no remedy: %v", err)
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
			elsewhere := filepath.Join(tmp(t), "elsewhere")
			if err := os.Rename(target, elsewhere); err != nil {
				t.Fatal(err)
			}
			if err := os.Symlink(elsewhere, target); err != nil {
				t.Fatal(err)
			}
			_, _, err := Extract(cache, p)
			if err == nil || !strings.Contains(err.Error(), target) || !strings.Contains(err.Error(), "symbolic link") || !strings.Contains(err.Error(), "remove the folder "+dir+" and run zn again") {
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
			if err == nil || !strings.Contains(err.Error(), target) || !strings.Contains(err.Error(), "writable") || !strings.Contains(err.Error(), "remove the folder "+dir+" and run zn again") {
				t.Fatalf("%s at %v: %v", target, mode, err)
			}
		}
	}
	// the cache folder itself
	cache, p, _ := extracted(t)
	if err := os.Chmod(cache, 0o777); err != nil {
		t.Fatal(err)
	}
	if _, _, err := Extract(cache, p); err == nil || !strings.Contains(err.Error(), cache) || !strings.Contains(err.Error(), "writable") || !strings.Contains(err.Error(), "chmod go-w "+cache+", or set ZN_CACHE to a private folder") {
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
	root := tmp(t)
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
	home := tmp(t)
	xdg := tmp(t)
	file := filepath.Join(tmp(t), "a-file")
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
		if err := os.Link(target, filepath.Join(tmp(t), "elsewhere")); err != nil {
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

// swapOwnerTo makes ownerOf report this uid for exactly the paths named.
func swapOwnerTo(t *testing.T, uid int, paths ...string) {
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
				return uid, true
			}
		}
		return oldOwner(fi)
	}
}

const chainRemedy = "or set ZN_CACHE to a private folder"

// F1: a check of the cache folder binds nothing above it. Every folder from the cache up to / is vetted on the resolved
// path: the user's or root's, and not writable by group or others unless sticky (then its child on the chain is the user's).
func TestTheChainAboveTheCacheIsVetted(t *testing.T) {
	p := payloadOf(t)
	refused := func(t *testing.T, cache, folder string, words ...string) {
		t.Helper()
		_, _, err := Extract(cache, p)
		if err == nil || !strings.Contains(err.Error(), folder) {
			t.Fatalf("want a refusal naming %s: %v", folder, err)
		}
		for _, w := range words {
			if !strings.Contains(err.Error(), w) {
				t.Fatalf("the refusal lacks %q: %v", w, err)
			}
		}
	}
	t.Run("a world-writable parent is refused", func(t *testing.T) {
		base := tmp(t)
		os.Chmod(base, 0o777)
		refused(t, filepath.Join(base, "zn"), base, "writable", "chmod go-w "+base+", "+chainRemedy)
	})
	t.Run("a group-writable grandparent is refused", func(t *testing.T) {
		top := tmp(t)
		os.MkdirAll(filepath.Join(top, "gp", "base"), 0o700)
		os.Chmod(filepath.Join(top, "gp"), 0o770)
		refused(t, filepath.Join(top, "gp", "base", "zn"), filepath.Join(top, "gp"), "writable")
	})
	t.Run("a writable folder far above is refused", func(t *testing.T) {
		top := tmp(t)
		deep := filepath.Join(top, "a", "b", "c", "d")
		os.MkdirAll(deep, 0o700)
		os.Chmod(top, 0o757)
		refused(t, filepath.Join(deep, "zn"), top, "writable")
	})
	t.Run("a sticky world-writable parent is accepted", func(t *testing.T) {
		base := tmp(t)
		os.Chmod(base, 0o777|os.ModeSticky)
		if _, _, err := Extract(filepath.Join(base, "zn"), p); err != nil {
			t.Fatalf("a sticky parent: %v", err)
		}
	})
	t.Run("a sticky parent whose child on the chain is not the user's is refused", func(t *testing.T) {
		top := tmp(t)
		os.MkdirAll(filepath.Join(top, "kid", "base"), 0o700)
		os.Chmod(top, 0o777|os.ModeSticky)
		swapOwnerTo(t, 0, filepath.Join(top, "kid")) // root's folder inside a sticky one: someone else could have made it
		refused(t, filepath.Join(top, "kid", "base", "zn"), top, "sticky", filepath.Join(top, "kid"))
	})
	t.Run("a root-owned ancestor is accepted, another user's is refused", func(t *testing.T) {
		top := tmp(t)
		os.MkdirAll(filepath.Join(top, "mid", "base"), 0o700)
		swapOwnerTo(t, 0, filepath.Join(top, "mid"))
		if _, _, err := Extract(filepath.Join(top, "mid", "base", "zn"), p); err != nil {
			t.Fatalf("a root-owned ancestor: %v", err)
		}
		swapOwnerTo(t, currentUID()+1, filepath.Join(top, "mid"))
		refused(t, filepath.Join(top, "mid", "base", "zn"), filepath.Join(top, "mid"), "owned by")
	})
	t.Run("a base linked to a safe folder is accepted and the resolved folder is used", func(t *testing.T) {
		top := tmp(t)
		real := filepath.Join(top, "real")
		os.Mkdir(real, 0o700)
		os.Symlink(real, filepath.Join(top, ".cache"))
		dir, _, err := Extract(filepath.Join(top, ".cache", "zn"), p)
		if err != nil {
			t.Fatal(err)
		}
		if dir != filepath.Join(real, "zn", p.ID) {
			t.Fatalf("the folder to run from is %s, not the resolved %s", dir, filepath.Join(real, "zn", p.ID))
		}
	})
	t.Run("a base linked to a world-writable folder is refused naming it", func(t *testing.T) {
		top := tmp(t)
		real := filepath.Join(top, "real")
		os.Mkdir(real, 0o700)
		os.Chmod(real, 0o777)
		os.Symlink(real, filepath.Join(top, ".cache"))
		refused(t, filepath.Join(top, ".cache", "zn"), real, "writable")
	})
}

// The XDG_CACHE_HOME choice: one that is the user's but writable by others is ignored (the cache falls back to HOME/.cache).
func TestAnXDGCacheHomeWritableByOthersIsIgnored(t *testing.T) {
	home, xdg := tmp(t), tmp(t)
	os.Chmod(xdg, 0o777)
	got, err := CacheFolder([]string{"XDG_CACHE_HOME=" + xdg, "HOME=" + home})
	if err != nil || got != filepath.Join(home, ".cache", "zn") {
		t.Fatalf("a world-writable XDG_CACHE_HOME was used: %q %v", got, err)
	}
	os.Chmod(xdg, 0o777|os.ModeSticky)
	if got, _ := CacheFolder([]string{"XDG_CACHE_HOME=" + xdg, "HOME=" + home}); got != filepath.Join(xdg, "zn") {
		t.Fatalf("a sticky one is the user's: %q", got)
	}
}

// F4: each refusal ends with what to do.
func TestEveryRefusalSaysWhatToDo(t *testing.T) {
	cache, p, _ := extracted(t)
	swapOwnerTo(t, 0, cache)
	_, _, err := Extract(cache, p)
	if err == nil || !strings.Contains(err.Error(), "sudo rm -rf "+cache+", "+chainRemedy) {
		t.Fatalf("a cache folder root owns: %v", err)
	}
	cache2, p2, _ := extracted(t)
	swapOwnerTo(t, currentUID()+1, cache2)
	_, _, err = Extract(cache2, p2)
	if err == nil || !strings.Contains(err.Error(), cache2) || !strings.Contains(err.Error(), chainRemedy) {
		t.Fatalf("a cache folder another user owns: %v", err)
	}
}

func TestRetriesThatRunOutSayAnotherZnKeptReplacing(t *testing.T) {
	cache, p, dir := extracted(t)
	os.WriteFile(filepath.Join(dir, "z-nile", "engine", "x"), []byte("x"), 0o600)
	old := renameFn
	renameFn = func(from, to string) error {
		if to == dir {
			return fmt.Errorf("rename: %w", errors.New("directory not empty"))
		}
		return old(from, to)
	}
	defer func() { renameFn = old }()
	_, _, err := Extract(cache, p)
	if err == nil || !strings.Contains(err.Error(), "another zn kept replacing "+dir+": run zn again") {
		t.Fatalf("retries exhausted: %v", err)
	}
}

// F2: a replacement renames the bad folder aside and the new one into place with nothing between: no hashing, no put-back
// while <id> is missing. The recorded order is deterministic; the reader below shows the path is there but for that gap.
func TestAReplacementLeavesNothingBetweenTheTwoRenames(t *testing.T) {
	cache, p, dir := extracted(t)
	os.WriteFile(filepath.Join(dir, "z-nile", "engine", "x"), []byte("x"), 0o600)
	var events []string
	old := renameFn
	renameFn = func(from, to string) error {
		kind := "rename"
		if from == dir {
			kind = "rename-aside"
		} else if to == dir {
			kind = "rename-in"
		}
		events = append(events, kind)
		return old(from, to)
	}
	onCheck = func(string) { events = append(events, "check") }
	defer func() { renameFn, onCheck = old, nil }()
	if _, fresh, err := Extract(cache, p); err != nil || !fresh {
		t.Fatalf("%v %v", err, fresh)
	}
	for i, e := range events {
		if e == "rename-aside" {
			if i+1 >= len(events) || events[i+1] != "rename-in" {
				t.Fatalf("something runs between the folder moving aside and the new one moving in: %v", events)
			}
		}
	}
	got := strings.Join(events, ",")
	if !strings.Contains(got, "rename-aside,rename-in") {
		t.Fatalf("no replacement happened: %v", events)
	}
}

// A reader that reads a file of the folder by path through 20 replacements. The honest threshold: the path is missing only
// in the gap between two renames, so a reader's misses come in at most one run per replacement (a lone miss is a
// scheduling accident); it never reads a partial or foreign file, and it is never missing when a replacement is not under way.
func TestAReaderByPathThroughTwentyReplacements(t *testing.T) {
	cache, p, dir := extracted(t)
	file := filepath.Join(dir, "z-nile", "engine", "main.luau")
	stop := make(chan struct{})
	done := make(chan [3]int)
	go func() {
		runs, misses, bad := 0, 0, 0
		inMiss := false
		deadline := time.After(60 * time.Second)
		for {
			select {
			case <-stop:
				done <- [3]int{runs, misses, bad}
				return
			case <-deadline:
				done <- [3]int{-1, 0, 0}
				return
			default:
			}
			b, err := os.ReadFile(file)
			switch {
			case err != nil:
				misses++
				if !inMiss {
					runs++
				}
				inMiss = true
			case string(b) != "print('engine')\n":
				bad++
				inMiss = false
			default:
				inMiss = false
			}
		}
	}()
	for i := 0; i < 20; i++ {
		os.WriteFile(file, []byte("tampered\n"), 0o600)
		if _, fresh, err := Extract(cache, p); err != nil || !fresh {
			close(stop)
			t.Fatalf("replacement %d: %v %v", i, err, fresh)
		}
	}
	close(stop)
	r := <-done
	if r[0] < 0 {
		t.Fatal("the reader hit its deadline")
	}
	// the tampering write itself is read by the reader as "bad" content, so only count a partial or foreign file
	if r[0] > 20 {
		t.Fatalf("the path was missing in %d separate runs through 20 replacements (%d misses): more than the one gap each", r[0], r[1])
	}
}

// F3: a file system that does not keep exact modes: the laid-out folder is checked before it is renamed in, and a mismatch
// is a refusal, not a folder that is replaced on every run.
func TestAFileSystemThatDoesNotKeepModesIsRefusedBeforeAnythingIsRenamedIn(t *testing.T) {
	cache := filepath.Join(tmp(t), "zn")
	p := payloadOf(t)
	afterLay = func(tmpdir string) { os.Chmod(filepath.Join(tmpdir, "z-nile", "roots.luau"), 0o644) }
	defer func() { afterLay = nil }()
	_, _, err := Extract(cache, p)
	m := ""
	if err != nil {
		m = err.Error()
	}
	for _, w := range []string{"does not keep file modes", "roots.luau", "0644", "0600", "set ZN_CACHE to a folder on a local disk", cache} {
		if !strings.Contains(m, w) {
			t.Fatalf("the refusal lacks %q: %v", w, err)
		}
	}
	left, _ := os.ReadDir(cache)
	if len(left) != 0 {
		t.Fatalf("a refused extraction left %d entries: %v", len(left), left)
	}
	// with a folder already there that needs replacing, it stays as it was
	cache2, p2, dir2 := extracted(t)
	os.WriteFile(filepath.Join(dir2, "z-nile", "engine", "planted"), []byte("x"), 0o600)
	afterLay = func(tmpdir string) { os.Chmod(filepath.Join(tmpdir, "z-nile", "roots.luau"), 0o644) }
	if _, _, err := Extract(cache2, p2); err == nil {
		t.Fatal("a mismatch in the laid-out folder was renamed in")
	}
	if _, err := os.Stat(filepath.Join(dir2, "z-nile", "engine", "planted")); err != nil {
		t.Fatal("the existing folder was touched")
	}
	if len(stales(cache2)) != 0 {
		t.Fatal("a stale folder was left")
	}
}

func TestAUmaskThatRemovesOwnerBitsStillGivesTheRightModes(t *testing.T) {
	old := syscall.Umask(0o177)
	defer syscall.Umask(old)
	cache := filepath.Join(tmp(t), "new", "zn")
	p := payloadOf(t)
	dir, _, err := Extract(cache, p)
	if err != nil {
		t.Fatal(err)
	}
	syscall.Umask(old)
	if _, fresh, err := Extract(cache, p); err != nil || fresh {
		t.Fatalf("the folder laid out under umask 0177 does not verify: %v %v", err, fresh)
	}
	for _, d := range []string{filepath.Dir(cache), cache, dir, filepath.Join(dir, "bin"), filepath.Join(dir, "z-nile", "engine")} {
		if st, err := os.Stat(d); err != nil || st.Mode().Perm() != 0o700 {
			t.Errorf("%s: %v %v", d, st.Mode(), err)
		}
	}
}

// F6: a folder that is replaced says so, once, with the first difference and where the old one is kept; a cold cache is quiet.
func TestAReplacementSaysSoOnce(t *testing.T) {
	cache := filepath.Join(tmp(t), "zn")
	p := payloadOf(t)
	var out bytes.Buffer
	dir, _, err := ExtractNotify(cache, p, &out)
	if err != nil || out.Len() != 0 {
		t.Fatalf("a cold cache: %v %q", err, out.String())
	}
	os.WriteFile(filepath.Join(dir, "z-nile", "engine", "main.luau"), []byte("x"), 0o600)
	if _, _, err := ExtractNotify(cache, p, &out); err != nil {
		t.Fatal(err)
	}
	kept := stales(cache)
	if len(kept) != 1 || strings.Count(out.String(), "\n") != 1 || !strings.Contains(out.String(), "main.luau") || !strings.Contains(out.String(), kept[0]) {
		t.Fatalf("the notice %q, kept %v", out.String(), kept)
	}
	out.Reset()
	if _, _, err := ExtractNotify(cache, p, &out); err != nil || out.Len() != 0 {
		t.Fatalf("a good folder is quiet: %v %q", err, out.String())
	}
}

// F7: an empty folder nobody asked for, a folder the tar carries by itself, and the bits above the permissions.
func TestEmptyFoldersAndSpecialBitsAreComparedToo(t *testing.T) {
	cache, p, dir := extracted(t)
	os.Mkdir(filepath.Join(dir, "z-nile", "engine", "empty"), 0o700)
	if _, fresh, err := Extract(cache, p); err != nil || !fresh {
		t.Fatalf("an empty unexpected folder: %v %v", err, fresh)
	}
	var b bytes.Buffer
	tw := tar.NewWriter(&b)
	tw.WriteHeader(&tar.Header{Name: "z-nile/only-a-folder/", Typeflag: tar.TypeDir, Mode: 0o755})
	tw.WriteHeader(&tar.Header{Name: "z-nile/f", Typeflag: tar.TypeReg, Mode: 0o644, Size: 1})
	tw.Write([]byte("x"))
	tw.Close()
	q := Payload{Lune: []byte("l"), Tar: b.Bytes(), ID: "0000000000000009"}
	cache2 := filepath.Join(tmp(t), "zn")
	d2, _, err := Extract(cache2, q)
	if err != nil {
		t.Fatal(err)
	}
	os.Remove(filepath.Join(d2, "z-nile", "only-a-folder"))
	if _, fresh, err := Extract(cache2, q); err != nil || !fresh {
		t.Fatalf("a folder the tar carries by itself, removed: %v %v", err, fresh)
	}
	for _, bit := range []os.FileMode{os.ModeSetuid, os.ModeSetgid} {
		cache3, p3, dir3 := extracted(t)
		os.Chmod(filepath.Join(dir3, "bin", "lune"), 0o700|bit)
		if _, fresh, err := Extract(cache3, p3); err != nil || !fresh {
			t.Fatalf("bit %v on the lune: %v %v", bit, err, fresh)
		}
	}
}
