package main

import (
	"archive/tar"
	"bytes"
	"errors"
	"fmt"
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
	// The test process's own PATH holds a decoy lune first (TestMain), so a zn that looked `lune` up there would be
	// caught on every machine, with or without a real Lune installed.
	lune := []byte("#!/bin/sh\n")
	tarBytes := packTree(t)
	p := payload.Payload{Lune: lune, Tar: tarBytes, ID: payload.ID(lune, tarBytes)}
	f.d = deps{
		embedded: func() (payload.Payload, bool) { return p, embedded },
		exec: func(path string, argv, env []string) error {
			f.execs = append(f.execs, execCall{path, argv, env})
			return f.err
		},
		env:    []string{"HOME=" + resolved(t), "PATH=/usr/bin:/bin"},
		cwd:    func() (string, error) { return resolved(t), nil },
		chdir:  func(string) error { return nil },
		stdout: &f.out,
		stderr: &f.errOut,
	}
	return f
}

// TestMain gives every test of this package one environment, set before any test runs, so the tests can run in
// parallel without setting a variable: PATH with a decoy lune first (a zn that looked `lune` up on PATH would run it
// and fail) and a stub ssh (no test reaches a network), and a HOME whose git config holds an identity and nothing else (zn init commits as the user). The PATH and
// HOME the binary started with stay in startPath and startHome, where findLune looks for the pinned Lune.
func TestMain(m *testing.M) {
	decoy, err := os.MkdirTemp("", "zn-decoy-")
	if err == nil {
		err = os.WriteFile(filepath.Join(decoy, "lune"), []byte("#!/bin/sh\nexit 97\n"), 0o755)
	}
	if err == nil { // and an ssh that never reaches a network (sshStub)
		decoySSHPids = filepath.Join(decoy, "ssh-pids")
		err = os.WriteFile(filepath.Join(decoy, "ssh"), []byte(sshStub(decoySSHPids)), 0o755)
	}
	home, err2 := os.MkdirTemp("", "zn-home-")
	if err2 == nil {
		home, err2 = filepath.EvalSymlinks(home)
	}
	if err2 == nil {
		err2 = os.WriteFile(filepath.Join(home, ".gitconfig"), []byte("[user]\n\tname = T\n\temail = t@users.noreply.github.com\n"), 0o644)
	}
	if err != nil || err2 != nil {
		fmt.Fprintln(os.Stderr, err, err2)
		os.Exit(2)
	}
	os.Setenv("PATH", decoy+":/usr/bin:/bin")
	os.Setenv("HOME", home)
	os.Setenv("XDG_CONFIG_HOME", filepath.Join(home, ".config"))
	// the engine run in-process never gets the terminal go test may have been started from, and no test stops its
	// own process group (a helper process that tests stopping sets both back)
	if null, err := os.Open(os.DevNull); err == nil {
		childStdin = null
	}
	stopGroup = func() { panic("a test in this process would have stopped its own process group") }
	code := m.Run()
	os.RemoveAll(decoy)
	os.RemoveAll(home)
	os.Exit(code)
}

// resolved is a fresh folder with no link in its path (macOS's /var is one), so paths in messages are comparable.
func resolved(t *testing.T) string {
	t.Helper()
	d, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return d
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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
	t.Parallel()
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

func TestAFailedExecNamesZNCache(t *testing.T) {
	t.Parallel()
	f := newFake(t, true)
	f.err = errors.New("operation not permitted")
	if code := run([]string{"list"}, f.d); code != 4 {
		t.Fatalf("exit %d", code)
	}
	m := f.errOut.String()
	folder := filepath.Join(homeOf(f), ".cache", "zn", mustID(f))
	if !strings.Contains(m, "ZN_CACHE") || !strings.Contains(m, folder) || !strings.Contains(m, "noexec") {
		t.Fatalf("message %q lacks the folder %s, noexec or ZN_CACHE", m, folder)
	}
}

// F10: an unset or empty PATH becomes <dir>/bin plus the system default, never the extracted folder alone, and an empty
// entry (which means the current folder) never appears.
func TestPathEdgeCases(t *testing.T) {
	t.Parallel()
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
	t.Parallel()
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

// f0427 step 2: a deleted lune is put back before the engine starts, never blamed on a noexec mount.
func TestAMissingLuneIsPutBackBeforeTheEngineStarts(t *testing.T) {
	t.Parallel()
	f := newFake(t, true)
	f.d.env = append(f.d.env, "ZN_CACHE="+filepath.Join(homeOf(f), "c"))
	run([]string{"list"}, f.d)
	lune := filepath.Join(homeOf(f), "c", "zn", mustID(f), "bin", "lune")
	os.Remove(lune)
	f.errOut.Reset()
	if code := run([]string{"list"}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	if b, err := os.ReadFile(lune); err != nil || string(b) != "#!/bin/sh\n" {
		t.Fatalf("the lune was not put back: %v %q", err, b)
	}
}

// f0427 step 2 (F14): a changed lune is never the program that runs. The fake exec reads the file it is asked to run at
// the moment of the call: the mutant that executes first and re-extracts afterwards, or not at all, shows the decoy.
func TestATamperedLuneIsNeverExecuted(t *testing.T) {
	t.Parallel()
	f := newFake(t, true)
	f.d.env = append(f.d.env, "ZN_CACHE="+filepath.Join(homeOf(f), "c"))
	var atExec [][]byte
	f.d.exec = func(path string, argv, env []string) error {
		b, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		atExec = append(atExec, b)
		return nil
	}
	run([]string{"list"}, f.d)
	lune := filepath.Join(homeOf(f), "c", "zn", mustID(f), "bin", "lune")
	os.WriteFile(lune, []byte("#!/bin/sh\ntouch decoy-ran\n"), 0o700)
	if code := run([]string{"list"}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	if len(atExec) != 2 || string(atExec[1]) != "#!/bin/sh\n" {
		t.Fatalf("the second run started %q", atExec)
	}
}

func TestAnUnsafeCacheIsRefusedWithAMessageNamingTheFolderAndNothingStarts(t *testing.T) {
	t.Parallel()
	f := newFake(t, true)
	base := filepath.Join(homeOf(f), "c")
	f.d.env = append(f.d.env, "ZN_CACHE="+base)
	run([]string{"list"}, f.d)
	cache := filepath.Join(base, "zn")
	os.Chmod(cache, 0o777)
	f.errOut.Reset()
	before := len(f.execs)
	if code := run([]string{"list"}, f.d); code != 4 {
		t.Fatalf("exit %d", code)
	}
	if !strings.Contains(f.errOut.String(), cache) || !strings.Contains(f.errOut.String(), "ZN_CACHE") || len(f.execs) != before {
		t.Fatalf("message %q, execs %d -> %d", f.errOut.String(), before, len(f.execs))
	}
}

func TestARelativeXDGCacheHomeIsIgnoredAndWritesNothingBesideTheWorkingFolder(t *testing.T) {
	f := newFake(t, true)
	work := resolved(t)
	t.Chdir(work)
	f.d.env = append(f.d.env, "XDG_CACHE_HOME=rel/cache")
	if code := run([]string{"list"}, f.d); code != 0 {
		t.Fatalf("exit %d: %s", code, f.errOut.String())
	}
	if _, err := os.Stat(filepath.Join(work, "rel")); err == nil {
		t.Fatal("the relative XDG_CACHE_HOME was used")
	}
	if _, err := os.Stat(filepath.Join(homeOf(f), ".cache", "zn", mustID(f), "bin", "lune")); err != nil {
		t.Fatalf("the payload is not under HOME/.cache: %v", err)
	}
}

func TestHomeUnsetIsAClearMessageAndNothingStarts(t *testing.T) {
	t.Parallel()
	f := newFake(t, true)
	f.d.env = []string{"PATH=/usr/bin:/bin"}
	if code := run([]string{"list"}, f.d); code != 4 {
		t.Fatalf("exit %d", code)
	}
	m := f.errOut.String()
	if !strings.Contains(m, "HOME") || !strings.Contains(m, "ZN_CACHE") || len(f.execs) != 0 {
		t.Fatalf("message %q execs %d", m, len(f.execs))
	}
}

// F5: zn's own refusals exit 4, a code the engine does not use (it uses 1 constantly, and 3 is "no payload").
func TestEveryCacheRefusalExitsFour(t *testing.T) {
	t.Parallel()
	f := newFake(t, true)
	f.d.env = append(f.d.env, "ZN_CACHE=relative")
	if code := run([]string{"list"}, f.d); code != 4 {
		t.Fatalf("a relative ZN_CACHE: exit %d", code)
	}
	if code := run([]string{"list"}, deps{embedded: f.d.embedded, exec: f.d.exec, env: []string{}, stdout: &f.out, stderr: &f.errOut}); code != 4 {
		t.Fatalf("no HOME: exit %d", code)
	}
	f2 := newFake(t, true)
	f2.err = errors.New("operation not permitted")
	if code := run([]string{"list"}, f2.d); code != 4 {
		t.Fatalf("a failed exec: exit %d", code)
	}
}
