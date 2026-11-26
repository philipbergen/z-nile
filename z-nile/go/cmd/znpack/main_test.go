package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"znile/internal/payload"
)

func digest(b []byte) string { h := sha256.Sum256(b); return hex.EncodeToString(h[:]) }

func fixture(t *testing.T, luneBody string) (opts options, sumText string) {
	root := t.TempDir()
	for _, f := range []string{"z-nile/engine/main.luau", "z-nile/lib/x.sh", "z-nile/vendor/v.js", "z-nile/templates/t.md", "z-nile/roots.luau", "z-nile/affected.luau"} {
		p := filepath.Join(root, f)
		os.MkdirAll(filepath.Dir(p), 0o755)
		os.WriteFile(p, []byte("x "+f), 0o644)
	}
	for _, args := range [][]string{{"init", "-q", "-b", "main"}, {"add", "-A"}, {"-c", "user.name=t", "-c", "user.email=t@example.invalid", "commit", "-qm", "f"}} {
		cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
		cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null")
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v %s", args, err, out)
		}
	}
	var zb bytes.Buffer
	zw := zip.NewWriter(&zb)
	w, _ := zw.Create("lune")
	w.Write([]byte(luneBody))
	zw.Close()
	zipPath := filepath.Join(t.TempDir(), "lune.zip")
	os.WriteFile(zipPath, zb.Bytes(), 0o644)
	sumText = "zip linux-x86_64 " + digest(zb.Bytes()) + " lune.zip\n"
	sumPath := filepath.Join(t.TempDir(), "lune.sum")
	os.WriteFile(sumPath, []byte(sumText), 0o644)
	return options{root: root, sum: sumPath, goos: "linux", goarch: "amd64", zip: zipPath, out: filepath.Join(t.TempDir(), "embedded")}, sumText
}

func TestPackWritesTheThreeEmbeddedFiles(t *testing.T) {
	o, _ := fixture(t, "linux lune")
	if err := build(o, io.Discard); err != nil {
		t.Fatal(err)
	}
	lune, _ := os.ReadFile(filepath.Join(o.out, "lune"))
	tarBytes, _ := os.ReadFile(filepath.Join(o.out, "engine.tar"))
	meta, _ := os.ReadFile(filepath.Join(o.out, "meta"))
	if string(lune) != "linux lune" {
		t.Fatalf("lune %q", lune)
	}
	p := payload.New(lune, tarBytes, string(meta))
	if p.Kind != "zip" || p.Dirty {
		t.Fatalf("meta %q", meta)
	}
	for _, name := range []string{"z-nile/engine/main.luau", "z-nile/lib/x.sh", "z-nile/vendor/v.js", "z-nile/templates/t.md", "z-nile/roots.luau", "z-nile/affected.luau"} {
		if !bytes.Contains(tarBytes, []byte(name)) {
			t.Errorf("the tar lacks %s", name)
		}
	}
}

func TestAZipThatDoesNotMatchTheSumWritesNothing(t *testing.T) {
	o, _ := fixture(t, "linux lune")
	// the sum pins another zip: the build must refuse, say which platform, and leave no embedded file
	other := []byte("zip linux-x86_64 " + strings.Repeat("0", 64) + " lune.zip\n")
	os.WriteFile(o.sum, other, 0o644)
	err := build(o, io.Discard)
	if err == nil || !strings.Contains(err.Error(), "linux-x86_64") {
		t.Fatalf("a mismatched zip was accepted: %v", err)
	}
	if _, serr := os.Stat(filepath.Join(o.out, "lune")); serr == nil {
		t.Fatal("a refused build left a Lune behind")
	}
}

func TestNoLuneSuppliedIsRefusedWithAMessageNamingThePlatform(t *testing.T) {
	o, _ := fixture(t, "x")
	o.zip = ""
	err := build(o, io.Discard)
	if err == nil || !strings.Contains(err.Error(), "no Lune") || !strings.Contains(err.Error(), "linux-x86_64") {
		t.Fatalf("no lune: %v", err)
	}
}

func TestAPlatformNotInTheSumIsRefused(t *testing.T) {
	o, _ := fixture(t, "x")
	o.goarch = "arm64"
	if err := build(o, io.Discard); err == nil || !strings.Contains(err.Error(), "linux-aarch64") {
		t.Fatalf("an unpinned platform: %v", err)
	}
}

func TestUncommittedEditsAreReportedAndMarkedDirty(t *testing.T) {
	o, _ := fixture(t, "linux lune")
	os.WriteFile(filepath.Join(o.root, "z-nile/engine/main.luau"), []byte("edited"), 0o644)
	var log bytes.Buffer
	if err := build(o, &log); err != nil {
		t.Fatal(err)
	}
	meta, _ := os.ReadFile(filepath.Join(o.out, "meta"))
	if !strings.Contains(string(meta), "dirty 1") || !strings.Contains(log.String(), "uncommitted") {
		t.Fatalf("meta %q log %q", meta, log.String())
	}
}
