package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// goSources lists the files a live spec's watch file must name: every non-test .go file under goRoot and its go.mod, as
// repository-relative paths (prefix names goRoot's place, "z-nile/go").
func goSources(goRoot, prefix string) ([]string, error) {
	var out []string
	err := filepath.WalkDir(goRoot, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return err
		}
		name := d.Name()
		if (strings.HasSuffix(name, ".go") && !strings.HasSuffix(name, "_test.go")) || name == "go.mod" {
			rel, _ := filepath.Rel(goRoot, p)
			out = append(out, prefix+"/"+filepath.ToSlash(rel))
		}
		return nil
	})
	sort.Strings(out)
	return out, err
}

// unwatched names the sources a watch file does not list, as one message ("" when it lists them all).
func unwatched(watch string, sources []string) string {
	listed := map[string]bool{}
	for _, l := range strings.Split(watch, "\n") {
		listed[strings.TrimSpace(l)] = true
	}
	var missing []string
	for _, s := range sources {
		if !listed[s] {
			missing = append(missing, s)
		}
	}
	return strings.Join(missing, ", ")
}

// F9: every live spec's watch file names every non-test Go source and go.mod, so a change to the Go module selects them.
// This runs in the Go stage whenever z-nile/go is touched (a Luau spec's own watch file could not name a file not yet written).
func TestLiveSpecsWatchEveryGoSource(t *testing.T) {
	goRoot, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	specs := filepath.Join(goRoot, "..", "tests", "tooling")
	if _, err := os.Stat(specs); err != nil {
		t.Skipf("no specs beside the module: %v", err)
	}
	sources, err := goSources(goRoot, "z-nile/go")
	if err != nil || len(sources) < 10 {
		t.Fatalf("the Go sources: %d %v", len(sources), err)
	}
	for _, name := range []string{"live-cli", "live-autostart", "livecall"} {
		b, err := os.ReadFile(filepath.Join(specs, name+".watch.txt"))
		if err != nil {
			t.Fatal(err)
		}
		if missing := unwatched(string(b), sources); missing != "" {
			t.Errorf("%s.watch.txt does not name: %s", name, missing)
		}
	}
}

// F9: a scratch Go file that no watch file names is reported by name.
func TestScratchGoFileIsReported(t *testing.T) {
	root := t.TempDir()
	os.MkdirAll(filepath.Join(root, "internal", "x"), 0o755)
	for _, f := range []string{"go.mod", "main.go", "main_test.go", "internal/x/x.go"} {
		os.WriteFile(filepath.Join(root, f), []byte("x"), 0o644)
	}
	sources, _ := goSources(root, "z-nile/go")
	watch := "z-nile/go/go.mod\nz-nile/go/main.go\nz-nile/go/internal/x/x.go\n"
	if m := unwatched(watch, sources); m != "" {
		t.Fatalf("a complete watch file reported: %s", m)
	}
	os.WriteFile(filepath.Join(root, "internal", "x", "scratch.go"), []byte("x"), 0o644)
	sources, _ = goSources(root, "z-nile/go")
	if m := unwatched(watch, sources); m != "z-nile/go/internal/x/scratch.go" {
		t.Fatalf("the scratch file was not named: %q", m)
	}
}
