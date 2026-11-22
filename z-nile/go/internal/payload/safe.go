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

// ownedFolder: dir exists (a link to a folder counts: the user chose it), the current user owns it and neither group nor
// others can write it (unless it is sticky, as /tmp is). A folder that is not safe is ignored, and the cache falls back.
func ownedFolder(dir string) bool {
	fi, err := os.Stat(dir)
	if err != nil || !fi.IsDir() {
		return false
	}
	if fi.Mode().Perm()&0o022 != 0 && fi.Mode()&os.ModeSticky == 0 {
		return false
	}
	uid, ok := ownerOf(fi)
	return ok && uid == currentUID()
}

// vetError is a refusal; kind says which rule, so the remedy can fit it.
type vetError struct {
	kind string // link, type, owner, hardlink, writable, sticky
	path string
	root bool // the owner is root
	msg  string
}

func (e *vetError) Error() string { return e.msg }

// vet refuses what zn will not run from: a link, a file of another kind than expected, one another user owns, or one that
// group or others can write. The error names the path.
func vet(p string, fi os.FileInfo, wantDir bool) error {
	switch {
	case fi.Mode()&os.ModeSymlink != 0:
		return &vetError{kind: "link", path: p, msg: fmt.Sprintf("payload: %s is a symbolic link: zn will not run from a cache that links elsewhere", p)}
	case wantDir && !fi.IsDir():
		return &vetError{kind: "type", path: p, msg: fmt.Sprintf("payload: %s is not a folder", p)}
	case !wantDir && !fi.Mode().IsRegular():
		return &vetError{kind: "type", path: p, msg: fmt.Sprintf("payload: %s is not a regular file", p)}
	}
	if uid, ok := ownerOf(fi); !ok || uid != currentUID() {
		return &vetError{kind: "owner", path: p, root: ok && uid == 0, msg: fmt.Sprintf("payload: %s is owned by user %d, not by you (user %d)", p, uid, currentUID())}
	}
	if !wantDir {
		if st, ok := fi.Sys().(*syscall.Stat_t); ok && st.Nlink != 1 {
			return &vetError{kind: "hardlink", path: p, msg: fmt.Sprintf("payload: %s has %d hard links: its other names could change it", p, st.Nlink)}
		}
	}
	if fi.Mode().Perm()&0o022 != 0 {
		return &vetError{kind: "writable", path: p, msg: fmt.Sprintf("payload: %s is writable by group or others (%v)", p, fi.Mode().Perm())}
	}
	return nil
}

// inCache adds the remedy for a refusal of a folder on the way to the cache, or the cache folder itself.
func inCache(err error) error {
	var v *vetError
	if !errors.As(err, &v) {
		return err
	}
	var fix string
	switch {
	case v.kind == "writable":
		fix = "chmod go-w " + v.path + ", or set ZN_CACHE to a private folder"
	case v.kind == "owner" && v.root:
		fix = "sudo rm -rf " + v.path + ", or set ZN_CACHE to a private folder"
	case v.kind == "owner":
		fix = "have its owner remove it, or set ZN_CACHE to a private folder"
	default:
		fix = "remove " + v.path + ", or set ZN_CACHE to a private folder"
	}
	return fmt.Errorf("%w: %s", err, fix)
}

// inID adds the remedy for a refusal inside the extracted folder.
func inID(dir string, err error) error {
	var v *vetError
	if !errors.As(err, &v) {
		return err
	}
	return fmt.Errorf("%w: remove the folder %s and run zn again", err, dir)
}

// mkdir700All makes dir and its missing parents, each exactly 0700 whatever the umask.
func mkdir700All(dir string) error {
	if fi, err := os.Stat(dir); err == nil {
		if !fi.IsDir() {
			return fmt.Errorf("%s is not a folder", dir)
		}
		return nil
	}
	if parent := filepath.Dir(dir); parent != dir {
		if err := mkdir700All(parent); err != nil {
			return err
		}
	}
	if err := os.Mkdir(dir, 0o700); err != nil && !errors.Is(err, fs.ErrExist) {
		return err
	}
	return os.Chmod(dir, 0o700)
}

// resolveCache makes the folder that holds the cache, then returns the cache's path with every link above it resolved. A
// base that is a link (~/.cache pointing at another disk) is allowed; what it points at is then vetted like any ancestor.
func resolveCache(cache string) (string, error) {
	base := filepath.Dir(cache)
	if err := mkdir700All(base); err != nil {
		return "", fmt.Errorf("payload: the cache folder %s: %w", cache, err)
	}
	rb, err := filepath.EvalSymlinks(base)
	if err != nil {
		return "", fmt.Errorf("payload: the cache folder %s: %w", cache, err)
	}
	return filepath.Join(rb, filepath.Base(cache)), nil
}

// ensureCache makes the cache folder 0700 and vets it and every folder above it, up to / (cache is resolved). A folder
// above is the user's or root's, and not writable by group or others unless sticky, in which case the next folder down the
// chain must be the user's: otherwise someone else could replace the tree after it was checked.
func ensureCache(cache string) (err error) {
	fi, err := os.Lstat(cache)
	if errors.Is(err, fs.ErrNotExist) {
		defer func() {
			if err != nil {
				os.Remove(cache) // made just now and refused: leave nothing behind (it is empty)
			}
		}()
		if err := mkdir700All(cache); err != nil {
			return fmt.Errorf("payload: the cache folder %s: %w", cache, err)
		}
		fi, err = os.Lstat(cache)
	}
	if err != nil {
		return fmt.Errorf("payload: the cache folder %s: %w", cache, err)
	}
	if err := vet(cache, fi, true); err != nil {
		return inCache(err)
	}
	child := cache
	for d := filepath.Dir(cache); ; d = filepath.Dir(d) {
		fi, err := os.Lstat(d)
		if err != nil {
			return fmt.Errorf("payload: %s: %w", d, err)
		}
		if fi.Mode()&os.ModeSymlink != 0 || !fi.IsDir() {
			return inCache(vet(d, fi, true))
		}
		uid, ok := ownerOf(fi)
		if !ok || (uid != currentUID() && uid != 0) {
			return inCache(&vetError{kind: "owner", path: d, root: false, msg: fmt.Sprintf("payload: %s is owned by user %d, not by you (user %d) or root", d, uid, currentUID())})
		}
		if fi.Mode().Perm()&0o022 != 0 {
			if fi.Mode()&os.ModeSticky == 0 {
				return inCache(&vetError{kind: "writable", path: d, msg: fmt.Sprintf("payload: %s is writable by group or others (%v), so someone else could replace the cache below it", d, fi.Mode().Perm())})
			}
			if cfi, err := os.Lstat(child); err != nil {
				return fmt.Errorf("payload: %s: %w", child, err)
			} else if cuid, ok := ownerOf(cfi); !ok || cuid != currentUID() {
				return inCache(&vetError{kind: "sticky", path: d, msg: fmt.Sprintf("payload: %s is sticky and writable by others, and %s below it on the way to the cache is owned by user %d, not by you", d, child, cuid)})
			}
		}
		if d == filepath.Dir(d) {
			return nil
		}
		child = d
	}
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
	lune := p.luneDigest()
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
	if onCheck != nil {
		onCheck(dir)
	}
	fi, err := os.Lstat(dir)
	if errors.Is(err, fs.ErrNotExist) {
		return noFolder, nil
	}
	if err != nil {
		return "", fmt.Errorf("payload: %s: %w", dir, err)
	}
	if err := vet(dir, fi, true); err != nil {
		return "", inID(dir, err)
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
			return inID(dir, err)
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
		case bits(fi.Mode()) != uint32(f.perm):
			note(fmt.Sprintf("%s is %04o, not %04o", rel, bits(fi.Mode()), uint32(f.perm)))
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

// noFolder is check's answer for a folder that is not there (a cold cache), not a difference worth telling the user.
const noFolder = "the folder does not exist"

// bits is the mode as chmod writes it: the permissions plus setuid, setgid and sticky.
func bits(m os.FileMode) uint32 {
	b := uint32(m.Perm())
	if m&os.ModeSetuid != 0 {
		b |= 0o4000
	}
	if m&os.ModeSetgid != 0 {
		b |= 0o2000
	}
	if m&os.ModeSticky != 0 {
		b |= 0o1000
	}
	return b
}

// Seams the replacement's order is tested through.
var renameFn = os.Rename

var onCheck func(dir string)
