package payload

import (
	"archive/tar"
	"bytes"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"
	"syscall"
)

// This file is the cache's safety (f0427 step 2): which folder is the cache, whether it is the user's own, and whether
// what is in it is what the program carries. Extract (payload.go) uses it on every run.

// currentUID and ownerOf are the seams the ownership rule is tested through: a test cannot make a file another user's
// without root, so it swaps these.
var currentUID = func() int { return os.Getuid() }

var ownerOf = func(fi os.FileInfo) (int, bool) {
	st, ok := fi.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, false
	}
	return int(st.Uid), true
}

// CacheFolder is where the payload is extracted: <base>/zn. <base> is ZN_CACHE when set (it must be absolute), else
// XDG_CACHE_HOME when it is absolute and a folder the user owns, else $HOME/.cache (HOME must be set and absolute). A
// relative or foreign XDG_CACHE_HOME is ignored, as the XDG specification asks of a relative one.
func CacheFolder(env []string) (string, error) {
	get := func(k string) string {
		for _, e := range env {
			if v, ok := strings.CutPrefix(e, k+"="); ok {
				return v
			}
		}
		return ""
	}
	if v := get("ZN_CACHE"); v != "" {
		if !filepath.IsAbs(v) {
			return "", fmt.Errorf("ZN_CACHE is %q: it must be an absolute path", v)
		}
		return filepath.Join(v, "zn"), nil
	}
	if v := get("XDG_CACHE_HOME"); filepath.IsAbs(v) && ownedFolder(v) {
		return filepath.Join(v, "zn"), nil
	}
	switch h := get("HOME"); {
	case h == "":
		return "", errors.New("HOME is not set, so zn has no cache folder: set HOME, or set ZN_CACHE to an absolute folder")
	case !filepath.IsAbs(h):
		return "", fmt.Errorf("HOME is %q: it must be an absolute path (or set ZN_CACHE to an absolute folder)", h)
	default:
		return filepath.Join(h, ".cache", "zn"), nil
	}
}

// ownedFolder: dir exists (a link to a folder counts: the user chose it) and the current user owns it.
func ownedFolder(dir string) bool {
	fi, err := os.Stat(dir)
	if err != nil || !fi.IsDir() {
		return false
	}
	uid, ok := ownerOf(fi)
	return ok && uid == currentUID()
}

// vet refuses what zn will not run from: a link, a file of another kind than expected, one another user owns, or one that
// group or others can write. The error names the path.
func vet(p string, fi os.FileInfo, wantDir bool) error {
	switch {
	case fi.Mode()&os.ModeSymlink != 0:
		return fmt.Errorf("payload: %s is a symbolic link: zn will not run from a cache that links elsewhere", p)
	case wantDir && !fi.IsDir():
		return fmt.Errorf("payload: %s is not a folder", p)
	case !wantDir && !fi.Mode().IsRegular():
		return fmt.Errorf("payload: %s is not a regular file", p)
	}
	if uid, ok := ownerOf(fi); !ok || uid != currentUID() {
		return fmt.Errorf("payload: %s is owned by user %d, not by you (user %d)", p, uid, currentUID())
	}
	if !wantDir {
		if st, ok := fi.Sys().(*syscall.Stat_t); ok && st.Nlink != 1 {
			return fmt.Errorf("payload: %s has %d hard links: its other names could change it", p, st.Nlink)
		}
	}
	if fi.Mode().Perm()&0o022 != 0 {
		return fmt.Errorf("payload: %s is writable by group or others (%v): run chmod go-w on it, or use another cache folder", p, fi.Mode().Perm())
	}
	return nil
}

// ensureCache makes the cache folder (and any missing parent) 0700 and vets it.
func ensureCache(cache string) error {
	fi, err := os.Lstat(cache)
	if errors.Is(err, fs.ErrNotExist) {
		if err := os.MkdirAll(cache, 0o700); err != nil {
			return fmt.Errorf("payload: the cache folder %s: %w", cache, err)
		}
		fi, err = os.Lstat(cache)
	}
	if err != nil {
		return fmt.Errorf("payload: the cache folder %s: %w", cache, err)
	}
	return vet(cache, fi, true)
}

// want is what a good extracted folder holds.
type want struct {
	files map[string]wantFile // slash path relative to the folder
	dirs  map[string]bool
}

type wantFile struct {
	size int64
	sum  [32]byte
	perm os.FileMode
}

// eachEntry walks the engine tar, refusing what a payload never carries: an escaping name, a link, a special file.
func eachEntry(p Payload, fn func(name string, h *tar.Header, r io.Reader) error) error {
	tr := tar.NewReader(bytes.NewReader(p.Tar))
	for {
		h, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return fmt.Errorf("payload: the engine tar: %w", err)
		}
		name := path.Clean(h.Name)
		if path.IsAbs(name) || name == ".." || strings.HasPrefix(name, "../") {
			return fmt.Errorf("payload: the entry %q would escape the cache folder", h.Name)
		}
		if h.Typeflag != tar.TypeDir && h.Typeflag != tar.TypeReg {
			return fmt.Errorf("payload: the entry %q is a link or special file, which the engine tar never carries", h.Name)
		}
		if err := fn(name, h, tr); err != nil {
			return err
		}
	}
}

func permOf(h *tar.Header) os.FileMode {
	if h.Mode&0o111 != 0 {
		return 0o700
	}
	return 0o600
}

func dirsOf(name string, dirs map[string]bool) {
	for d := path.Dir(name); d != "." && d != "/"; d = path.Dir(d) {
		dirs[d] = true
	}
}

// wantOf is the manifest of the payload: every file with its size, sha256 and mode, every folder, from the embedded bytes.
func wantOf(p Payload) (want, error) {
	w := want{files: map[string]wantFile{}, dirs: map[string]bool{"bin": true}}
	lune := sha256.Sum256(p.Lune)
	w.files["bin/lune"] = wantFile{int64(len(p.Lune)), lune, 0o700}
	marker := []byte(p.ID + "\n")
	w.files[Marker] = wantFile{int64(len(marker)), sha256.Sum256(marker), 0o600}
	err := eachEntry(p, func(name string, h *tar.Header, r io.Reader) error {
		dirsOf(name, w.dirs)
		if h.Typeflag == tar.TypeDir {
			w.dirs[name] = true
			return nil
		}
		hash := sha256.New()
		n, err := io.Copy(hash, r)
		if err != nil {
			return fmt.Errorf("payload: the engine tar: %w", err)
		}
		var sum [32]byte
		copy(sum[:], hash.Sum(nil))
		w.files[name] = wantFile{n, sum, permOf(h)}
		return nil
	})
	return w, err
}

// check vets the extracted folder dir and compares it with w. A refusal (a link, a foreign owner, a writable bit, a file
// of another kind) is the error. A folder that is merely not the payload (a file missing, changed, truncated, added) is a
// non-empty mismatch naming the first difference; "" says the folder is the payload's, byte for byte.
func check(dir string, w want) (mismatch string, refused error) {
	fi, err := os.Lstat(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return "the folder does not exist", nil
	}
	if err != nil {
		return "", fmt.Errorf("payload: %s: %w", dir, err)
	}
	if err := vet(dir, fi, true); err != nil {
		return "", err
	}
	seen := 0
	note := func(s string) {
		if mismatch == "" {
			mismatch = s
		}
	}
	walkErr := filepath.WalkDir(dir, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			note(fmt.Sprintf("%s: %v", p, err))
			return nil
		}
		if p == dir {
			return nil
		}
		fi, err := d.Info()
		if err != nil {
			note(fmt.Sprintf("%s: %v", p, err))
			return nil
		}
		rel, _ := filepath.Rel(dir, p)
		rel = filepath.ToSlash(rel)
		if err := vet(p, fi, fi.IsDir()); err != nil {
			return err
		}
		if fi.IsDir() {
			if !w.dirs[rel] {
				note("an unexpected folder " + rel)
			}
			return nil
		}
		f, ok := w.files[rel]
		switch {
		case !ok:
			note("an unexpected file " + rel)
		case fi.Size() != f.size:
			note(fmt.Sprintf("%s has %d bytes, not %d", rel, fi.Size(), f.size))
		case fi.Mode().Perm() != f.perm:
			note(fmt.Sprintf("%s has mode %v, not %v", rel, fi.Mode().Perm(), f.perm))
		default:
			seen++
			if mismatch == "" && !sameDigest(p, fi, f.sum) {
				note(rel + " differs from the embedded file")
			}
		}
		return nil
	})
	if walkErr != nil {
		return "", walkErr
	}
	if mismatch == "" && seen != len(w.files) {
		mismatch = "a file is missing"
	}
	if mismatch == "" {
		for d := range w.dirs {
			if fi, err := os.Lstat(filepath.Join(dir, filepath.FromSlash(d))); err != nil || !fi.IsDir() {
				mismatch = "the folder " + d + " is missing"
				break
			}
		}
	}
	return mismatch, nil
}

// sameDigest hashes the file that was vetted: the opened handle must be the very file fi described.
func sameDigest(file string, fi os.FileInfo, sum [32]byte) bool {
	if beforeOpen != nil {
		beforeOpen(file)
	}
	f, err := os.Open(file)
	if err != nil {
		return false
	}
	defer f.Close()
	if opened, err := f.Stat(); err != nil || !os.SameFile(fi, opened) {
		return false
	}
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return false
	}
	return bytes.Equal(h.Sum(nil), sum[:])
}

// beforeOpen is a test seam: it runs between vetting a file and opening it for its digest.
var beforeOpen func(path string)
