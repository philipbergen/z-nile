// Package payload is what a zn release binary carries: one platform's Lune and a tar of the Luau engine. It packs the
// tar deterministically, names the payload by its content, and extracts it once to a cache folder, atomically.
package payload

import (
	"archive/tar"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"strings"
	"time"
)

// Marker is the file whose presence says an extracted folder is complete.
const Marker = ".ok"

// Payload is the embedded runtime: the platform's Lune binary, the engine tar and the content id naming them.
type Payload struct {
	Lune  []byte
	Tar   []byte
	ID    string // the content id of Lune and Tar, computed from the bytes
	Kind  string // the pin kind of the Lune ("zip" or "bin"), as the build recorded it
	Dirty bool   // the build packed uncommitted edits

	luneSum [32]byte // the sha256 of Lune when New computed it for the id; zero otherwise
}

// New builds the Payload of the embedded bytes. The id is computed here from the bytes; meta is the build's small text
// file ("kind zip|bin" and, for a build from a tree with uncommitted edits, "dirty 1").
func New(lune, tarBytes []byte, meta string) Payload {
	l, t := sha256.Sum256(lune), sha256.Sum256(tarBytes)
	p := Payload{Lune: lune, Tar: tarBytes, ID: idOf(l, t), Kind: "unknown", luneSum: l}
	for _, line := range strings.Split(meta, "\n") {
		k, v, _ := strings.Cut(strings.TrimSpace(line), " ")
		switch k {
		case "kind":
			p.Kind = v
		case "dirty":
			p.Dirty = v == "1"
		}
	}
	return p
}

// LuneSum is the first 16 hex digits of the sha256 of the embedded Lune.
func (p Payload) LuneSum() string {
	h := p.luneDigest()
	return hex.EncodeToString(h[:])[:16]
}

// luneDigest is the sha256 of the Lune: the one New took when it is there, else computed.
func (p Payload) luneDigest() [32]byte {
	if p.luneSum != ([32]byte{}) {
		return p.luneSum
	}
	return sha256.Sum256(p.Lune)
}

// ID is the content id of a Lune and an engine tar: the first 16 hex digits of the sha256 of both digests, so a changed
// byte in either gives another id (and another cache folder).
func ID(lune, tarBytes []byte) string {
	return idOf(sha256.Sum256(lune), sha256.Sum256(tarBytes))
}

func idOf(l, t [32]byte) string {
	h := sha256.Sum256(append(l[:], t[:]...))
	return hex.EncodeToString(h[:])[:16]
}

// Pack writes a deterministic tar of the files git tracks under the given paths (relative to root, which is a git
// checkout): no times, no owners, mode 0755 or 0644 from the index, content from the working tree. Ignored and untracked
// files are never packed. dirty reports a tracked file under the paths that differs from the index or HEAD. It refuses a
// path with no tracked file, a tracked link and a tracked file missing from the working tree.
func Pack(root string, paths []string, w io.Writer) (dirty bool, err error) {
	tw := tar.NewWriter(w)
	for _, p := range paths {
		out, err := gitOut(root, "ls-files", "-s", "-z", "--", p)
		if err != nil {
			return false, fmt.Errorf("payload: %s: %w", p, err)
		}
		entries := strings.Split(strings.TrimSuffix(out, "\x00"), "\x00")
		if out == "" {
			return false, fmt.Errorf("payload: no tracked file under %s in %s", p, root)
		}
		for _, e := range entries {
			meta, name, ok := strings.Cut(e, "\t")
			if !ok || len(meta) < 6 {
				return false, fmt.Errorf("payload: unreadable git entry %q", e)
			}
			mode := meta[:6]
			if mode == "120000" {
				return false, fmt.Errorf("payload: %s is a link, and the engine tar carries none", name)
			}
			if mode != "100644" && mode != "100755" {
				return false, fmt.Errorf("payload: %s has git mode %s, not a regular file", name, mode)
			}
			if path.Base(name) == ".DS_Store" {
				continue
			}
			body, err := os.ReadFile(filepath.Join(root, filepath.FromSlash(name)))
			if err != nil {
				return false, fmt.Errorf("payload: %s is tracked but unreadable: %w", name, err)
			}
			tmode := int64(0o644)
			if mode == "100755" {
				tmode = 0o755
			}
			if err := tw.WriteHeader(&tar.Header{Typeflag: tar.TypeReg, Name: name, Mode: tmode, Size: int64(len(body)), ModTime: time.Unix(0, 0)}); err != nil {
				return false, err
			}
			if _, err := tw.Write(body); err != nil {
				return false, err
			}
		}
		st, err := gitOut(root, "status", "--porcelain", "--untracked-files=no", "--", p)
		if err != nil {
			return false, fmt.Errorf("payload: %s: %w", p, err)
		}
		if st != "" {
			dirty = true
		}
	}
	return dirty, tw.Close()
}

func gitOut(root string, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("git %s: %v: %s", strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return stdout.String(), nil
}

// afterLay is a test seam: it runs once the temporary folder is complete, before it is renamed into place.
var afterLay func(tmp string)

// Extract is ExtractNotify with no notice.
func Extract(cache string, p Payload) (dir string, fresh bool, err error) {
	return ExtractNotify(cache, p, nil)
}

// ExtractNotify returns the folder <cache>/<id> holding the payload, laying it out when it is not there as the program
// carries it. The cache is resolved once (every link above it followed) and the resolved folder is the one returned and run
// from; the cache folder is made 0700 and it and every folder up to / are vetted (see ensureCache and vet): a link, a folder
// another user owns or one group or others can write is refused with an error naming it and saying what to do. Every call
// compares what is extracted with the payload (the sha256 of the Lune and of every engine file, sizes, modes, and nothing
// added), so a changed, truncated, deleted or added file is found before anything runs; the folder is then replaced.
//
// It works in a temporary folder beside the result, checks that laid-out folder too (a file system that does not keep modes
// is refused there, not replaced on every run) and renames it into place, so a failure leaves no <id> folder and a reader
// never sees half of one. It never removes a folder another zn may be running from: a folder that fails the comparison is
// renamed aside and the new one renamed into place at once, with nothing between the two renames (a reader by path misses a
// file only in that gap, and no hashing happens while <id> is missing). The aside folder's modified time is set to now first,
// so the sweep leaves it for an hour, and it is removed at once only when it has no Marker, so was never a finished folder.
// A good folder that appears while this one works (another run finished first) is used as it is (fresh is false). When a
// folder that existed is replaced, one line saying so goes to notice (when not nil). Leftovers older than an hour are swept.
func ExtractNotify(cache string, p Payload, notice io.Writer) (dir string, fresh bool, err error) {
	w, err := wantOf(p)
	if err != nil {
		return "", false, err
	}
	if cache, err = resolveCache(cache); err != nil {
		return "", false, err
	}
	if err := ensureCache(cache); err != nil {
		return "", false, err
	}
	dir = filepath.Join(cache, p.ID)
	first, err := check(dir, w)
	if err != nil {
		return "", false, err
	}
	if first == "" {
		return dir, false, nil
	}
	tmp, err := os.MkdirTemp(cache, ".extract-")
	if err != nil {
		return "", false, fmt.Errorf("payload: %w", err)
	}
	defer os.RemoveAll(tmp) // after a successful rename it removes nothing
	defer sweep(cache)
	if err := lay(tmp, p); err != nil {
		return "", false, err
	}
	if afterLay != nil {
		afterLay(tmp)
	}
	if m, err := check(tmp, w); err != nil {
		return "", false, err
	} else if m != "" {
		return "", false, fmt.Errorf("payload: the file system at %s does not keep file modes (%s): set ZN_CACHE to a folder on a local disk", cache, m)
	}
	var aside string
	for attempt := 0; attempt < 8; attempt++ { // runs racing on one tampered folder may each take a turn
		if err := renameFn(tmp, dir); err == nil {
			kept := ""
			if aside != "" {
				if marked(aside) {
					kept = aside
				} else {
					os.RemoveAll(aside) // never finished, so never run from
				}
			}
			if notice != nil && first != noFolder {
				if kept != "" {
					fmt.Fprintf(notice, "zn: the cache folder %s did not match the payload (%s): replaced it; the old one is kept at %s\n", dir, first, kept)
				} else {
					fmt.Fprintf(notice, "zn: the cache folder %s did not match the payload (%s): replaced it\n", dir, first)
				}
			}
			return dir, true, nil
		}
		m, err := check(dir, w)
		if err != nil {
			return "", false, err
		}
		if m == "" { // another run finished first: its complete folder is as good as ours
			return dir, false, nil
		}
		if _, err := os.Lstat(dir); err != nil {
			continue // it was moved aside meanwhile: the place is free, take it
		}
		// <id> exists and is not the payload: move it aside, and the next turn renames the new folder in at once.
		a, merr := os.MkdirTemp(cache, ".stale-")
		if merr != nil {
			return "", false, fmt.Errorf("payload: %w", merr)
		}
		if err := os.Remove(a); err != nil {
			return "", false, fmt.Errorf("payload: %w", err)
		}
		now := time.Now() // before the move, so nothing sits between the two renames
		os.Chtimes(dir, now, now)
		if renameFn(dir, a) == nil {
			aside = a
		}
	}
	return "", false, fmt.Errorf("payload: another zn kept replacing %s: run zn again", dir)
}

func marked(dir string) bool {
	_, err := os.Stat(filepath.Join(dir, Marker))
	return err == nil
}

// sweep removes temporary and stale folders in the cache that are older than an hour, so a killed run's leftovers do not
// pile up. A younger one may be in use by another zn.
func sweep(cache string) {
	entries, err := os.ReadDir(cache)
	if err != nil {
		return
	}
	for _, e := range entries {
		n := e.Name()
		if !e.IsDir() || !(strings.HasPrefix(n, ".extract-") || strings.HasPrefix(n, ".stale-")) {
			continue
		}
		if info, err := e.Info(); err == nil && time.Since(info.ModTime()) > time.Hour {
			os.RemoveAll(filepath.Join(cache, n))
		}
	}
}

func lay(tmp string, p Payload) error {
	if err := os.Chmod(tmp, 0o700); err != nil {
		return err
	}
	if err := mkdir700All(filepath.Join(tmp, "bin")); err != nil {
		return err
	}
	if err := writeFile(filepath.Join(tmp, "bin", "lune"), p.Lune, 0o700); err != nil {
		return err
	}
	err := eachEntry(p, func(name string, h *tar.Header, r io.Reader) error {
		target := filepath.Join(tmp, filepath.FromSlash(name))
		if h.Typeflag == tar.TypeDir {
			return mkdir700All(target)
		}
		if err := mkdir700All(filepath.Dir(target)); err != nil {
			return err
		}
		f, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, permOf(h))
		if err != nil {
			return err
		}
		if _, err := io.Copy(f, r); err != nil {
			f.Close()
			return err
		}
		if err := f.Chmod(permOf(h)); err != nil { // a umask must not change the mode the comparison expects
			f.Close()
			return err
		}
		return f.Close()
	})
	if err != nil {
		return err
	}
	return writeFile(filepath.Join(tmp, Marker), []byte(p.ID+"\n"), 0o600)
}

// writeFile writes a new file with exactly this mode, whatever the umask.
func writeFile(name string, b []byte, mode os.FileMode) error {
	if err := os.WriteFile(name, b, mode); err != nil {
		return err
	}
	return os.Chmod(name, mode)
}
