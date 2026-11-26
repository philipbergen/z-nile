package payload

import (
	"archive/tar"
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
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
	root := tmp(t)
	write(t, root, "z-nile/engine/main.luau", "print('engine')\n", 0o644)
	write(t, root, "z-nile/lib/run.sh", "#!/bin/sh\n", 0o755)
	write(t, root, "z-nile/roots.luau", "return {}\n", 0o644)
	git(t, root, "init", "-q", "-b", "main")
	git(t, root, "add", "-A")
	git(t, root, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", "fixture")
	return root
}

func git(t *testing.T, root string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

var paths = []string{"z-nile/engine", "z-nile/lib", "z-nile/roots.luau"}

func pack(t *testing.T, root string) []byte {
	t.Helper()
	var b bytes.Buffer
	if _, err := Pack(root, paths, &b); err != nil {
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
	git(t, root, "add", "-A")
	var b bytes.Buffer
	if _, err := Pack(root, paths, &b); err == nil || !strings.Contains(err.Error(), "link") {
		t.Fatalf("a symlink in the engine was packed: %v", err)
	}
}

func TestPackNamesAMissingPath(t *testing.T) {
	var b bytes.Buffer
	empty := tmp(t)
	git(t, empty, "init", "-q", "-b", "main")
	_, err := Pack(empty, []string{"z-nile/engine"}, &b)
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
	cache := filepath.Join(tmp(t), "zn")
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
	cache := filepath.Join(tmp(t), "zn")
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
	cache := filepath.Join(tmp(t), "zn")
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
	_, _, err := Extract(filepath.Join(tmp(t), "zn"), Payload{Lune: []byte("x"), Tar: b.Bytes(), ID: "0000000000000001"})
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

// F1 (review 001): several zn processes starting on a cold cache must each end with a complete folder, and none may
// remove a folder another one finished. The mutant: RemoveAll of the target before the rename.
func TestConcurrentExtractNeverRemovesAFinishedFolder(t *testing.T) {
	for round := 0; round < 10; round++ {
		cache := filepath.Join(tmp(t), "zn")
		p := payloadOf(t)
		var wg sync.WaitGroup
		errs := make(chan error, 8)
		for i := 0; i < 8; i++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				dir, _, err := Extract(cache, p)
				if err != nil {
					errs <- err
					return
				}
				// every caller is about to exec from dir: the engine must still be there after the others finish
				time.Sleep(5 * time.Millisecond)
				if _, err := os.Stat(filepath.Join(dir, "z-nile", "engine", "main.luau")); err != nil {
					errs <- fmt.Errorf("the folder was removed after Extract returned it: %w", err)
				}
			}()
		}
		wg.Wait()
		close(errs)
		for err := range errs {
			t.Fatalf("round %d: %v", round, err)
		}
	}
}

func TestExtractSweepsOldLeftoversAndKeepsNewOnes(t *testing.T) {
	cache := filepath.Join(tmp(t), "zn")
	write(t, cache, ".extract-old/x", "x", 0o644)
	write(t, cache, ".stale-old/x", "x", 0o644)
	write(t, cache, ".extract-new/x", "x", 0o644)
	old := time.Now().Add(-2 * time.Hour)
	for _, n := range []string{".extract-old", ".stale-old"} {
		if err := os.Chtimes(filepath.Join(cache, n), old, old); err != nil {
			t.Fatal(err)
		}
	}
	if _, _, err := Extract(cache, payloadOf(t)); err != nil {
		t.Fatal(err)
	}
	for _, gone := range []string{".extract-old", ".stale-old"} {
		if _, err := os.Stat(filepath.Join(cache, gone)); err == nil {
			t.Errorf("%s older than an hour was not swept", gone)
		}
	}
	if _, err := os.Stat(filepath.Join(cache, ".extract-new")); err != nil {
		t.Error("a leftover younger than an hour (another process may be using it) was removed")
	}
}

func TestExtractLeavesNoStaleFolderAfterReplacingAnUnmarkedOne(t *testing.T) {
	cache := filepath.Join(tmp(t), "zn")
	p := payloadOf(t)
	write(t, filepath.Join(cache, p.ID), "stale.txt", "x", 0o644)
	if _, _, err := Extract(cache, p); err != nil {
		t.Fatal(err)
	}
	left, _ := filepath.Glob(filepath.Join(cache, ".stale-*"))
	if len(left) != 0 {
		t.Fatalf("stale folders left: %v", left)
	}
}

// F8: setuid, setgid and sticky bits in a tar header never survive extraction.
func TestExtractDropsSpecialModeBits(t *testing.T) {
	var b bytes.Buffer
	tw := tar.NewWriter(&b)
	for _, e := range []struct {
		name string
		mode int64
	}{{"z-nile/suid", 0o4755}, {"z-nile/sgid", 0o2755}, {"z-nile/sticky", 0o1755}, {"z-nile/plain", 0o644}} {
		tw.WriteHeader(&tar.Header{Name: e.name, Mode: e.mode, Size: 1, Typeflag: tar.TypeReg})
		tw.Write([]byte("x"))
	}
	tw.Close()
	dir, _, err := Extract(filepath.Join(tmp(t), "zn"), Payload{Lune: []byte("l"), Tar: b.Bytes(), ID: "0000000000000002"})
	if err != nil {
		t.Fatal(err)
	}
	for _, n := range []string{"suid", "sgid", "sticky", "plain"} {
		st, _ := os.Stat(filepath.Join(dir, "z-nile", n))
		if st.Mode()&(os.ModeSetuid|os.ModeSetgid|os.ModeSticky) != 0 {
			t.Errorf("%s kept a special bit: %v", n, st.Mode())
		}
		if st.Mode().Perm()&0o077 != 0 {
			t.Errorf("%s is readable or writable by others: %v", n, st.Mode())
		}
	}
}

// F8: a zip whose digest does not match is never opened as a zip. Bytes that are not a zip with a wrong pin must give the
// digest error; the mutant unzips first and gives a zip error.
func TestDigestIsComparedBeforeTheZipIsOpened(t *testing.T) {
	e := Entry{Kind: "zip", Platform: "linux-x86_64", SHA: strings.Repeat("0", 64)}
	_, err := e.Lune([]byte("this is not a zip at all"))
	if err == nil || !strings.Contains(err.Error(), "does not match lune.sum") {
		t.Fatalf("want the digest error, got %v", err)
	}
}

// F8: while an extraction is under way nothing is at <id> (a reader or a crash never sees half a folder), and a failed one
// leaves the cache as it found it, another id's finished folder included. The mutant lays straight into <id>.
func TestExtractWorksAsideAndAFailureLeavesTheCacheAsItWas(t *testing.T) {
	cache := filepath.Join(tmp(t), "zn")
	other := payloadOf(t)
	if _, _, err := Extract(cache, other); err != nil {
		t.Fatal(err)
	}
	var b bytes.Buffer
	tw := tar.NewWriter(&b)
	for i := 0; i < 2; i++ { // the second entry has the same name: O_EXCL refuses it midway
		tw.WriteHeader(&tar.Header{Name: "z-nile/dup", Mode: 0o644, Size: 1, Typeflag: tar.TypeReg})
		tw.Write([]byte("x"))
	}
	tw.Close()
	bad := Payload{Lune: []byte("l"), Tar: b.Bytes(), ID: "0000000000000003"}
	seen := false
	afterLay = func(tmp string) { seen = true }
	defer func() { afterLay = nil }()
	_, _, err := Extract(cache, bad)
	if err == nil {
		t.Fatal("a duplicate entry was accepted")
	}
	names, _ := os.ReadDir(cache)
	if len(names) != 1 || names[0].Name() != other.ID {
		t.Fatalf("the cache after a failed extract: %v", names)
	}
	_ = seen
	// a good one: at the moment the temporary folder is complete, <id> does not exist yet
	good := payloadOf(t)
	cache2 := filepath.Join(tmp(t), "zn")
	atHook := ""
	afterLay = func(tmp string) {
		_, serr := os.Stat(filepath.Join(cache2, good.ID))
		atHook = fmt.Sprintf("tmp=%s idExists=%v", filepath.Base(tmp), serr == nil)
	}
	if _, _, err := Extract(cache2, good); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(atHook, "idExists=false") || strings.Contains(atHook, "tmp="+good.ID) {
		t.Fatalf("the folder was laid in place: %s", atHook)
	}
}

// F7: the tar holds what git tracks. An ignored file and an untracked backup change nothing; a tracked edit changes the id
// and is reported as dirty.
func TestPackTakesOnlyTrackedFilesAndReportsUncommittedEdits(t *testing.T) {
	root := engineTree(t)
	write(t, root, ".gitignore", "*.swp\n", 0o644)
	git(t, root, "add", ".gitignore")
	git(t, root, "-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", "ignore")
	var clean bytes.Buffer
	dirty, err := Pack(root, paths, &clean)
	if err != nil || dirty {
		t.Fatalf("clean tree: dirty=%v err=%v", dirty, err)
	}
	write(t, root, "z-nile/engine/.main.luau.swp", "ignored", 0o644)
	write(t, root, "z-nile/engine/main.luau~", "an editor backup", 0o644)
	var same bytes.Buffer
	dirty, err = Pack(root, paths, &same)
	if err != nil || dirty || !bytes.Equal(clean.Bytes(), same.Bytes()) {
		t.Fatalf("ignored and untracked files changed the tar (dirty=%v err=%v)", dirty, err)
	}
	write(t, root, "z-nile/engine/main.luau", "print('edited, not committed')\n", 0o644)
	var edited bytes.Buffer
	dirty, err = Pack(root, paths, &edited)
	if err != nil || !dirty || bytes.Equal(clean.Bytes(), edited.Bytes()) {
		t.Fatalf("a tracked edit: dirty=%v err=%v same=%v", dirty, err, bytes.Equal(clean.Bytes(), edited.Bytes()))
	}
}

// F11: the id is computed from the embedded bytes, never read from a file the build wrote; the build's meta file says only
// the pin kind and whether the tree was dirty.
func TestNewComputesTheIDFromTheBytes(t *testing.T) {
	lune, tarBytes := []byte("l"), []byte("t")
	p := New(lune, tarBytes, "kind zip\ndirty 1\n")
	if p.ID != ID(lune, tarBytes) || p.Kind != "zip" || !p.Dirty {
		t.Fatalf("%+v", p)
	}
	q := New(lune, tarBytes, "kind bin\n")
	if q.ID != p.ID || q.Kind != "bin" || q.Dirty {
		t.Fatalf("%+v", q)
	}
	if New(lune, tarBytes, "").Kind != "unknown" {
		t.Fatal("a missing kind is not reported as unknown")
	}
}
