// Package payload is what a zn release binary carries: one platform's Lune and a tar of the Luau engine. It packs the
// tar deterministically, names the payload by its content, and extracts it once to a cache folder, atomically.
package payload

import (
	"archive/tar"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"
)

// Marker is the file whose presence says an extracted folder is complete.
const Marker = ".ok"

// Payload is the embedded runtime: the platform's Lune binary, the engine tar and the content id naming them.
type Payload struct {
	Lune []byte
	Tar  []byte
	ID   string
}

// ID is the content id of a Lune and an engine tar: the first 16 hex digits of the sha256 of both digests, so a changed
// byte in either gives another id (and another cache folder).
func ID(lune, tarBytes []byte) string {
	l, t := sha256.Sum256(lune), sha256.Sum256(tarBytes)
	h := sha256.Sum256(append(l[:], t[:]...))
	return hex.EncodeToString(h[:])[:16]
}

// Pack writes a deterministic tar of the given paths (files or folders, relative to root, in the order given and
// sorted within a folder): no times, no owners, mode 0755 or 0644. It refuses a missing path and any link.
func Pack(root string, paths []string, w io.Writer) error {
	tw := tar.NewWriter(w)
	for _, p := range paths {
		top := filepath.Join(root, filepath.FromSlash(p))
		if _, err := os.Lstat(top); err != nil {
			return fmt.Errorf("payload: %s: %w", p, err)
		}
		err := filepath.WalkDir(top, func(abs string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			rel, _ := filepath.Rel(root, abs)
			rel = filepath.ToSlash(rel)
			if d.Name() == ".DS_Store" {
				return nil
			}
			if d.Type()&fs.ModeSymlink != 0 {
				return fmt.Errorf("payload: %s is a link, and the engine tar carries none", rel)
			}
			if d.IsDir() {
				return tw.WriteHeader(&tar.Header{Typeflag: tar.TypeDir, Name: rel + "/", Mode: 0o755, ModTime: time.Unix(0, 0)})
			}
			info, err := d.Info()
			if err != nil {
				return err
			}
			if !info.Mode().IsRegular() {
				return fmt.Errorf("payload: %s is not a regular file", rel)
			}
			body, err := os.ReadFile(abs)
			if err != nil {
				return err
			}
			mode := int64(0o644)
			if info.Mode()&0o111 != 0 {
				mode = 0o755
			}
			if err := tw.WriteHeader(&tar.Header{Typeflag: tar.TypeReg, Name: rel, Mode: mode, Size: int64(len(body)), ModTime: time.Unix(0, 0)}); err != nil {
				return err
			}
			_, err = tw.Write(body)
			return err
		})
		if err != nil {
			return err
		}
	}
	return tw.Close()
}

// Extract lays the payload out as <cache>/<id>: bin/lune and the tar's entries, then the Marker. It does the work in a
// temporary folder beside the result and renames it into place, so a failure leaves no <id> folder, and a folder with
// the Marker is never touched again (fresh is false). A folder without the Marker is a leftover and is replaced.
func Extract(cache string, p Payload) (dir string, fresh bool, err error) {
	dir = filepath.Join(cache, p.ID)
	if _, err := os.Stat(filepath.Join(dir, Marker)); err == nil {
		return dir, false, nil
	}
	if err := os.MkdirAll(cache, 0o700); err != nil {
		return "", false, fmt.Errorf("payload: the cache folder %s: %w", cache, err)
	}
	tmp, err := os.MkdirTemp(cache, ".extract-")
	if err != nil {
		return "", false, fmt.Errorf("payload: %w", err)
	}
	defer os.RemoveAll(tmp) // after a successful rename it removes nothing
	if err := lay(tmp, p); err != nil {
		return "", false, err
	}
	if err := os.RemoveAll(dir); err != nil {
		return "", false, fmt.Errorf("payload: %w", err)
	}
	if err := os.Rename(tmp, dir); err != nil {
		// a concurrent run may have won the rename: its complete folder is as good as ours
		if _, serr := os.Stat(filepath.Join(dir, Marker)); serr == nil {
			return dir, false, nil
		}
		return "", false, fmt.Errorf("payload: %w", err)
	}
	return dir, true, nil
}

func lay(tmp string, p Payload) error {
	if err := os.Chmod(tmp, 0o700); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(tmp, "bin"), 0o700); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(tmp, "bin", "lune"), p.Lune, 0o700); err != nil {
		return err
	}
	tr := tar.NewReader(bytes.NewReader(p.Tar))
	for {
		h, err := tr.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			return fmt.Errorf("payload: the engine tar: %w", err)
		}
		name := path.Clean(h.Name)
		if path.IsAbs(name) || name == ".." || strings.HasPrefix(name, "../") {
			return fmt.Errorf("payload: the entry %q would escape the cache folder", h.Name)
		}
		target := filepath.Join(tmp, filepath.FromSlash(name))
		switch h.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o700); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o700); err != nil {
				return err
			}
			mode := os.FileMode(0o600)
			if h.Mode&0o111 != 0 {
				mode = 0o700
			}
			f, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
			if err != nil {
				return err
			}
			if _, err := io.Copy(f, tr); err != nil {
				f.Close()
				return err
			}
			if err := f.Close(); err != nil {
				return err
			}
		default:
			return fmt.Errorf("payload: the entry %q is a link or special file, which the engine tar never carries", h.Name)
		}
	}
	return os.WriteFile(filepath.Join(tmp, Marker), []byte(p.ID+"\n"), 0o600)
}
