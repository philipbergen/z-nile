package payload

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"path"
	"strings"
)

// Entry is one line of cmd/zn/lune.sum: how a platform's pinned Lune is checked. Kind is "zip" (SHA is the release
// zip's digest and the binary is its "lune" entry) or "bin" (SHA is the binary's own digest).
type Entry struct {
	Kind     string
	Platform string
	SHA      string
	Name     string
}

// ParseSum reads lune.sum: blank lines and # comments are skipped, every other line is "<kind> <platform> <sha256>
// <name>". It refuses an unknown kind, a digest that is not 64 hex digits and a repeated platform.
func ParseSum(text string) (map[string]Entry, error) {
	out := map[string]Entry{}
	for n, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Fields(line)
		if len(f) != 4 {
			return nil, fmt.Errorf("lune.sum line %d: want \"<kind> <platform> <sha256> <name>\", got %q", n+1, line)
		}
		e := Entry{Kind: f[0], Platform: f[1], SHA: f[2], Name: f[3]}
		if e.Kind != "zip" && e.Kind != "bin" {
			return nil, fmt.Errorf("lune.sum line %d: the kind is zip or bin, not %q", n+1, e.Kind)
		}
		if _, err := hex.DecodeString(e.SHA); err != nil || len(e.SHA) != 64 {
			return nil, fmt.Errorf("lune.sum line %d: %q is not a sha256 digest", n+1, e.SHA)
		}
		if _, dup := out[e.Platform]; dup {
			return nil, fmt.Errorf("lune.sum line %d: %s is listed twice", n+1, e.Platform)
		}
		out[e.Platform] = e
	}
	return out, nil
}

// Platform is the name lune.sum uses for a Go GOOS and GOARCH (Lune's own release naming).
func Platform(goos, goarch string) (string, error) {
	arch := map[string]string{"amd64": "x86_64", "arm64": "aarch64"}[goarch]
	if (goos != "linux" && goos != "darwin") || arch == "" {
		return "", fmt.Errorf("no Lune for %s/%s: zn supports linux and macOS on amd64 and arm64", goos, goarch)
	}
	return goos + "-" + arch, nil
}

// Lune checks data (the zip or the binary the entry names) against the pinned digest and returns the Lune binary. A
// digest that does not match is refused before anything is unpacked.
func (e Entry) Lune(data []byte) ([]byte, error) {
	got := sha256.Sum256(data)
	if hex.EncodeToString(got[:]) != e.SHA {
		return nil, fmt.Errorf("the Lune for %s does not match lune.sum: sha256 is %x, pinned %s", e.Platform, got, e.SHA)
	}
	if e.Kind == "bin" {
		return data, nil
	}
	zr, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
	if err != nil {
		return nil, fmt.Errorf("the Lune zip for %s: %w", e.Platform, err)
	}
	for _, f := range zr.File {
		if path.Base(f.Name) != "lune" || f.FileInfo().IsDir() {
			continue
		}
		rc, err := f.Open()
		if err != nil {
			return nil, err
		}
		defer rc.Close()
		return io.ReadAll(rc)
	}
	return nil, fmt.Errorf("the Lune zip for %s has no lune entry", e.Platform)
}
