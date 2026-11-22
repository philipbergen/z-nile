package main

import (
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
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "z-nile/engine"), 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(root, "z-nile/engine/main.luau"), []byte("print(1)\n"), 0o644)
	var b bytes.Buffer
	if err := payload.Pack(root, []string{"z-nile/engine"}, &b); err != nil {
		t.Fatal(err)
	}
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
	run([]string{"list"}, f.d)
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
