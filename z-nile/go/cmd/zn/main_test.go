package main

import (
	"archive/tar"
	"bytes"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"znile/internal/payload"
)

// fake is a run with a payload, a recording exec and a controlled environment.
type fake struct {
	d      deps
	out    bytes.Buffer
	errOut bytes.Buffer
	execs  []execCall
	err    error // what the fake exec returns
}

type execCall struct {
	path string
	argv []string
	env  []string
}

func newFake(t *testing.T, embedded bool) *fake {
	f := &fake{}
	// The test process's own PATH holds a decoy lune first, so a zn that looked `lune` up there would be caught on every
	// machine, with or without a real Lune installed.
	decoy := t.TempDir()
	os.WriteFile(filepath.Join(decoy, "lune"), []byte("#!/bin/sh\nexit 97\n"), 0o755)
	t.Setenv("PATH", decoy+":/usr/bin:/bin")
	lune := []byte("#!/bin/sh\n")
	tarBytes := packTree(t)
	p := payload.Payload{Lune: lune, Tar: tarBytes, ID: payload.ID(lune, tarBytes)}
	f.d = deps{
		embedded: func() (payload.Payload, bool) { return p, embedded },
		exec: func(path string, argv, env []string) error {
			f.execs = append(f.execs, execCall{path, argv, env})
			return f.err
		},
		env:    []string{"HOME=" + t.TempDir(), "PATH=/usr/bin:/bin"},
		stdout: &f.out,
		stderr: &f.errOut,
	}
	return f
}

func packTree(t *testing.T) []byte {
	var b bytes.Buffer
	tw := tar.NewWriter(&b)
	body := "print(1)\n"
	if err := tw.WriteHeader(&tar.Header{Name: "z-nile/engine/main.luau", Mode: 0o644, Size: int64(len(body)), Typeflag: tar.TypeReg}); err != nil {
		t.Fatal(err)
	}
	tw.Write([]byte(body))
	tw.Close()
	return b.Bytes()
}

func TestVersionRunsInGoWithoutExtracting(t *testing.T) {
	f := newFake(t, true)
	if code := run([]string{"version"}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	if !strings.HasPrefix(f.out.String(), "zn ") || !strings.Contains(f.out.String(), "payload ") {
		t.Fatalf("version printed %q", f.out.String())
	}
	if len(f.execs) != 0 {
		t.Fatal("version started the engine")
	}
	if _, err := os.Stat(filepath.Join(homeOf(f), ".cache")); err == nil {
		t.Fatal("version extracted the payload")
	}
}

func homeOf(f *fake) string {
	for _, e := range f.d.env {
		if v, ok := strings.CutPrefix(e, "HOME="); ok {
			return v
		}
	}
	return ""
}

func TestAnythingElseGoesToTheEngineUnderTheExtractedLune(t *testing.T) {
	f := newFake(t, true)
	f.d.env = append(f.d.env, "ZN_CACHE="+filepath.Join(homeOf(f), "c"))
	if code := run([]string{"list", "--all"}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	if len(f.execs) != 1 {
		t.Fatalf("%d execs", len(f.execs))
	}
	c := f.execs[0]
	dir := filepath.Join(homeOf(f), "c", "zn", mustID(f))
	if c.path != filepath.Join(dir, "bin", "lune") {
		t.Fatalf("exec path %s", c.path)
	}
	want := []string{filepath.Join(dir, "bin", "lune"), "run", filepath.Join(dir, "z-nile", "engine", "main"), "--", "list", "--all"}
	if strings.Join(c.argv, "\x00") != strings.Join(want, "\x00") {
		t.Fatalf("argv %q, want %q", c.argv, want)
	}
	// lune comes first on PATH, so the engine's own `lune` spawns find it when the machine has none
	var path string
	for _, e := range c.env {
		if v, ok := strings.CutPrefix(e, "PATH="); ok {
			path = v
		}
	}
	if path != filepath.Join(dir, "bin")+":/usr/bin:/bin" {
		t.Fatalf("PATH %q", path)
	}
}

func mustID(f *fake) string {
	p, _ := f.d.embedded()
	return p.ID
}

func TestTheSecondRunDoesNotExtractAgain(t *testing.T) {
	f := newFake(t, true)
	f.d.env = append(f.d.env, "ZN_CACHE="+filepath.Join(homeOf(f), "c"))
	run([]string{"list"}, f.d)
	lune := filepath.Join(homeOf(f), "c", "zn", mustID(f), "bin", "lune")
	first, _ := os.Stat(lune)
	// nothing may be written beside the extracted folder on a later run: a zn that extracts again cannot succeed here
	cacheDir := filepath.Join(homeOf(f), "c", "zn")
	if err := os.Chmod(cacheDir, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(cacheDir, 0o700) })
	f.errOut.Reset()
	if code := run([]string{"list"}, f.d); code != 0 {
		t.Fatalf("the second run needed to write: exit %d %s", code, f.errOut.String())
	}
	second, _ := os.Stat(lune)
	if !os.SameFile(first, second) || !first.ModTime().Equal(second.ModTime()) || len(f.execs) != 2 {
		t.Fatal("the second run extracted again, or did not start the engine")
	}
}

func TestABuildWithoutAPayloadSaysSoAndExitsThree(t *testing.T) {
	f := newFake(t, false)
	if code := run([]string{"list"}, f.d); code != 3 {
		t.Fatalf("exit %d", code)
	}
	msg := f.errOut.String()
	if !strings.Contains(msg, "no embedded Lune") || !strings.Contains(msg, "znbuild.sh") {
		t.Fatalf("message %q", msg)
	}
	if len(f.execs) != 0 {
		t.Fatal("it started something")
	}
	// version still works: it needs no engine
	if code := run([]string{"version"}, f.d); code != 0 || !strings.Contains(f.out.String(), "payload none") {
		t.Fatalf("version of a bare build: %d %q", code, f.out.String())
	}
}

func TestCacheFolderChoice(t *testing.T) {
	cases := []struct {
		env  []string
		want string
	}{
		{[]string{"ZN_CACHE=/z", "XDG_CACHE_HOME=/x", "HOME=/h"}, "/z/zn"},
		{[]string{"XDG_CACHE_HOME=/x", "HOME=/h"}, "/x/zn"},
		{[]string{"XDG_CACHE_HOME=relative/dir", "HOME=/h"}, "/h/.cache/zn"}, // a relative XDG_CACHE_HOME is ignored
		{[]string{"ZN_CACHE=relative", "HOME=/h"}, ""},                       // refused, never guessed
		{[]string{}, ""},
	}
	for _, c := range cases {
		got, err := cacheFolder(c.env)
		if c.want == "" {
			if err == nil {
				t.Errorf("%v: got %q, want a refusal", c.env, got)
			}
			continue
		}
		if err != nil || got != c.want {
			t.Errorf("%v: got %q %v, want %q", c.env, got, err, c.want)
		}
	}
}

func TestAFailedExecNamesZNCache(t *testing.T) {
	f := newFake(t, true)
	f.err = errors.New("operation not permitted")
	if code := run([]string{"list"}, f.d); code != 1 {
		t.Fatalf("exit %d", code)
	}
	if !strings.Contains(f.errOut.String(), "ZN_CACHE") {
		t.Fatalf("message %q", f.errOut.String())
	}
}

// F10: an unset or empty PATH becomes <dir>/bin plus the system default, never the extracted folder alone, and an empty
// entry (which means the current folder) never appears.
func TestPathEdgeCases(t *testing.T) {
	cases := []struct {
		env  []string
		want string
	}{
		{[]string{"HOME=/h"}, "/b:/usr/bin:/bin"},
		{[]string{"PATH="}, "/b:/usr/bin:/bin"},
		{[]string{"PATH=:/x::/y:"}, "/b:/x:/y"},
	}
	for _, c := range cases {
		var got string
		for _, e := range withLuneFirst(c.env, "/b") {
			if v, ok := strings.CutPrefix(e, "PATH="); ok {
				got = v
			}
		}
		if got != c.want {
			t.Errorf("%v: PATH %q, want %q", c.env, got, c.want)
		}
	}
}

// F5: version names the embedded Lune's digest and the kind of pin that was checked, and marks a dirty build.
func TestVersionNamesTheLuneAndMarksADirtyBuild(t *testing.T) {
	f := newFake(t, true)
	p, _ := f.d.embedded()
	p.Kind, p.Dirty = "bin", true
	f.d.embedded = func() (payload.Payload, bool) { return p, true }
	if code := run([]string{"version"}, f.d); code != 0 {
		t.Fatal(code)
	}
	out := f.out.String()
	if !strings.Contains(out, "payload "+p.ID+"-dirty") || !strings.Contains(out, "lune "+p.LuneSum()+" (bin pin)") {
		t.Fatalf("version printed %q", out)
	}
}

// F15: a marked folder whose lune was deleted is reported as missing, not blamed on a noexec mount.
func TestAMissingLuneIsReportedAsMissing(t *testing.T) {
	f := newFake(t, true)
	f.d.env = append(f.d.env, "ZN_CACHE="+filepath.Join(homeOf(f), "c"))
	run([]string{"list"}, f.d)
	os.Remove(filepath.Join(homeOf(f), "c", "zn", mustID(f), "bin", "lune"))
	f.errOut.Reset()
	if code := run([]string{"list"}, f.d); code != 1 {
		t.Fatalf("exit %d", code)
	}
	if !strings.Contains(f.errOut.String(), "is missing") || strings.Contains(f.errOut.String(), "noexec") {
		t.Fatalf("message %q", f.errOut.String())
	}
}
