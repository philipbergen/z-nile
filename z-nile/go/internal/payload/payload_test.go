package payload

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func write(t *testing.T, root, rel, text string, mode os.FileMode) {
	t.Helper()
	p := filepath.Join(root, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(text), mode); err != nil {
		t.Fatal(err)
	}
}

// engineTree makes a small checkout with the paths the engine tar carries.
func engineTree(t *testing.T) string {
	root := t.TempDir()
	write(t, root, "z-nile/engine/main.luau", "print('engine')\n", 0o644)
	write(t, root, "z-nile/lib/run.sh", "#!/bin/sh\n", 0o755)
	write(t, root, "z-nile/roots.luau", "return {}\n", 0o644)
	return root
}

var paths = []string{"z-nile/engine", "z-nile/lib", "z-nile/roots.luau"}

func pack(t *testing.T, root string) []byte {
	t.Helper()
	var b bytes.Buffer
	if err := Pack(root, paths, &b); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func TestPackIsDeterministicAndItsIDFollowsContent(t *testing.T) {
	root := engineTree(t)
	first := pack(t, root)
	// a newer mtime and a different owner change nothing in the tar
	later := time.Now().Add(time.Hour)
	if err := os.Chtimes(filepath.Join(root, "z-nile/engine/main.luau"), later, later); err != nil {
		t.Fatal(err)
	}
	second := pack(t, root)
	if !bytes.Equal(first, second) {
		t.Fatal("the tar differs although no content changed")
	}
	lune := []byte("lune-bytes")
	id := ID(lune, first)
	if len(id) != 16 {
		t.Fatalf("id %q is not 16 hex digits", id)
	}
	if ID(lune, second) != id {
		t.Fatal("same content, different id")
	}
	// one engine byte changes the id (the mutant: an id taken from the file names or the Lune alone)
	write(t, root, "z-nile/engine/main.luau", "print('engine!')\n", 0o644)
	if ID(lune, pack(t, root)) == id {
		t.Fatal("an engine change left the content id as it was")
	}
	// a different Lune changes it too
	if ID([]byte("other-lune"), first) == id {
		t.Fatal("a Lune change left the content id as it was")
	}
}

func TestPackKeepsTheExecBitAndRefusesLinks(t *testing.T) {
	root := engineTree(t)
	tr := tar.NewReader(bytes.NewReader(pack(t, root)))
	modes := map[string]int64{}
	for {
		h, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		modes[h.Name] = h.Mode
	}
	if modes["z-nile/lib/run.sh"] != 0o755 || modes["z-nile/engine/main.luau"] != 0o644 {
		t.Fatalf("modes %v", modes)
	}
	if err := os.Symlink("/etc/passwd", filepath.Join(root, "z-nile/engine/link")); err != nil {
		t.Fatal(err)
	}
	var b bytes.Buffer
	if err := Pack(root, paths, &b); err == nil || !strings.Contains(err.Error(), "link") {
		t.Fatalf("a symlink in the engine was packed: %v", err)
	}
}

func TestPackNamesAMissingPath(t *testing.T) {
	var b bytes.Buffer
	err := Pack(t.TempDir(), []string{"z-nile/engine"}, &b)
	if err == nil || !strings.Contains(err.Error(), "z-nile/engine") {
		t.Fatalf("a missing path: %v", err)
	}
}

func payloadOf(t *testing.T) Payload {
	lune := []byte("#!/bin/sh\necho lune\n")
	tarBytes := pack(t, engineTree(t))
	return Payload{Lune: lune, Tar: tarBytes, ID: ID(lune, tarBytes)}
}

func TestExtractLaysOutLuneAndEngineOnce(t *testing.T) {
	cache := filepath.Join(t.TempDir(), "zn")
	p := payloadOf(t)
	dir, fresh, err := Extract(cache, p)
	if err != nil || !fresh {
		t.Fatalf("first extract: %v fresh=%v", err, fresh)
	}
	if dir != filepath.Join(cache, p.ID) {
		t.Fatalf("dir %s", dir)
	}
	for _, f := range []string{"bin/lune", "z-nile/engine/main.luau", "z-nile/roots.luau", Marker} {
		if _, err := os.Stat(filepath.Join(dir, f)); err != nil {
			t.Fatalf("missing %s: %v", f, err)
		}
	}
	if st, _ := os.Stat(filepath.Join(dir, "bin/lune")); st.Mode()&0o111 == 0 {
		t.Fatal("the extracted lune is not executable")
	}
	if st, _ := os.Stat(filepath.Join(dir, "z-nile/lib/run.sh")); st.Mode()&0o100 == 0 {
		t.Fatal("an executable engine script lost its bit")
	}
	// the second run extracts nothing: a marker file's identity and mtime stay as they were
	before, _ := os.Stat(filepath.Join(dir, "bin/lune"))
	dir2, fresh2, err := Extract(cache, p)
	if err != nil || fresh2 || dir2 != dir {
		t.Fatalf("second extract: %v fresh=%v dir=%s", err, fresh2, dir2)
	}
	after, _ := os.Stat(filepath.Join(dir, "bin/lune"))
	if !os.SameFile(before, after) || !before.ModTime().Equal(after.ModTime()) {
		t.Fatal("the second run rewrote the extracted lune")
	}
}

func TestExtractIsAtomic(t *testing.T) {
	cache := filepath.Join(t.TempDir(), "zn")
	p := payloadOf(t)
	// a tar whose second entry escapes the folder: the first entry was written, yet no <id> folder may appear
	var b bytes.Buffer
	tw := tar.NewWriter(&b)
	for _, e := range []struct{ name, body string }{{"z-nile/ok.txt", "ok"}, {"../escape.txt", "no"}} {
		if err := tw.WriteHeader(&tar.Header{Name: e.name, Mode: 0o644, Size: int64(len(e.body)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		tw.Write([]byte(e.body))
	}
	tw.Close()
	bad := Payload{Lune: p.Lune, Tar: b.Bytes(), ID: "badbadbadbadbad0"}
	if _, _, err := Extract(cache, bad); err == nil || !strings.Contains(err.Error(), "escape") {
		t.Fatalf("an escaping entry was accepted: %v", err)
	}
	left, _ := os.ReadDir(cache)
	if len(left) != 0 {
		t.Fatalf("a failed extraction left %d entries in the cache", len(left))
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(cache), "escape.txt")); err == nil {
		t.Fatal("an entry was written outside the folder")
	}
}

func TestExtractReplacesAFolderWithNoMarker(t *testing.T) {
	cache := filepath.Join(t.TempDir(), "zn")
	p := payloadOf(t)
	half := filepath.Join(cache, p.ID)
	write(t, half, "stale.txt", "half of an extraction", 0o644)
	dir, fresh, err := Extract(cache, p)
	if err != nil || !fresh {
		t.Fatalf("extract: %v fresh=%v", err, fresh)
	}
	if _, err := os.Stat(filepath.Join(dir, "stale.txt")); err == nil {
		t.Fatal("the unmarked folder's leftover survived")
	}
}

func TestExtractRefusesALinkEntry(t *testing.T) {
	var b bytes.Buffer
	tw := tar.NewWriter(&b)
	tw.WriteHeader(&tar.Header{Name: "z-nile/l", Linkname: "/etc/passwd", Typeflag: tar.TypeSymlink})
	tw.Close()
	_, _, err := Extract(filepath.Join(t.TempDir(), "zn"), Payload{Lune: []byte("x"), Tar: b.Bytes(), ID: "0000000000000001"})
	if err == nil || !strings.Contains(err.Error(), "link") {
		t.Fatalf("a link entry: %v", err)
	}
}

func sum(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}

func TestParseSum(t *testing.T) {
	text := "# comment\n\nzip linux-x86_64 " + strings.Repeat("a", 64) + " lune-0.10.5-linux-x86_64.zip\nbin darwin-aarch64 " + strings.Repeat("b", 64) + " lune\n"
	m, err := ParseSum(text)
	if err != nil {
		t.Fatal(err)
	}
	if e := m["linux-x86_64"]; e.Kind != "zip" || e.SHA != strings.Repeat("a", 64) || e.Name != "lune-0.10.5-linux-x86_64.zip" {
		t.Fatalf("linux entry %+v", e)
	}
	for _, bad := range []string{
		"zip linux-x86_64 abc name\n",                                                        // a short digest
		"tgz linux-x86_64 " + strings.Repeat("a", 64) + " n\n",                               // an unknown kind
		"zip a " + strings.Repeat("a", 64) + " n\nzip a " + strings.Repeat("b", 64) + " n\n", // a repeated platform
		"zip linux-x86_64\n", // too few fields
	} {
		if _, err := ParseSum(bad); err == nil {
			t.Errorf("accepted %q", bad)
		}
	}
}

func zipOf(t *testing.T, name, body string) []byte {
	var b bytes.Buffer
	zw := zip.NewWriter(&b)
	w, err := zw.Create(name)
	if err != nil {
		t.Fatal(err)
	}
	w.Write([]byte(body))
	zw.Close()
	return b.Bytes()
}

func TestLuneFromBinChecksTheDigest(t *testing.T) {
	lune := []byte("a lune binary")
	e := Entry{Kind: "bin", Platform: "darwin-aarch64", SHA: sum(lune)}
	got, err := e.Lune(lune)
	if err != nil || !bytes.Equal(got, lune) {
		t.Fatalf("matching binary: %v", err)
	}
	if _, err := e.Lune([]byte("a different binary")); err == nil || !strings.Contains(err.Error(), "darwin-aarch64") {
		t.Fatalf("a binary that does not match lune.sum was accepted: %v", err)
	}
}

func TestLuneFromZipChecksTheZipThenTakesLune(t *testing.T) {
	z := zipOf(t, "lune", "linux lune bytes")
	e := Entry{Kind: "zip", Platform: "linux-x86_64", SHA: sum(z)}
	got, err := e.Lune(z)
	if err != nil || string(got) != "linux lune bytes" {
		t.Fatalf("matching zip: %q %v", got, err)
	}
	// the mutant: a build that unzips without checking the zip's digest
	if _, err := e.Lune(zipOf(t, "lune", "tampered")); err == nil || !strings.Contains(err.Error(), "sha256") {
		t.Fatalf("a zip that does not match lune.sum was accepted: %v", err)
	}
	empty := Entry{Kind: "zip", Platform: "linux-x86_64", SHA: sum(zipOf(t, "readme", "x"))}
	if _, err := empty.Lune(zipOf(t, "readme", "x")); err == nil || !strings.Contains(err.Error(), "lune") {
		t.Fatalf("a zip with no lune entry: %v", err)
	}
}

func TestPlatformNamesTheSumsKeys(t *testing.T) {
	for _, c := range []struct{ os, arch, want string }{
		{"linux", "amd64", "linux-x86_64"}, {"linux", "arm64", "linux-aarch64"},
		{"darwin", "arm64", "darwin-aarch64"}, {"darwin", "amd64", "darwin-x86_64"},
	} {
		got, err := Platform(c.os, c.arch)
		if err != nil || got != c.want {
			t.Errorf("%s/%s: %q %v", c.os, c.arch, got, err)
		}
	}
	if _, err := Platform("windows", "amd64"); err == nil {
		t.Error("windows was accepted")
	}
}
