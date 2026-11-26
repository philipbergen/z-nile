// Command znpack is the build's one step before `go build -tags zn_embed ./cmd/zn`: it checks a platform's Lune against
// lune.sum and writes the three files the binary embeds (lune, engine.tar and meta) to a folder. It refuses, and writes
// nothing, when the Lune does not match its pin or none was supplied.
package main

import (
	"bytes"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"znile/internal/payload"
)

// enginePaths are what the engine tar carries, relative to the checkout's top.
var enginePaths = []string{
	"z-nile/engine", "z-nile/lib", "z-nile/vendor", "z-nile/templates", "z-nile/roots.luau", "z-nile/affected.luau",
}

type options struct {
	root   string // the checkout the engine is read from
	sum    string // lune.sum
	goos   string // the target's GOOS
	goarch string // the target's GOARCH
	lune   string // a Lune binary (for a "bin" entry)
	zip    string // a Lune release zip (for a "zip" entry)
	out    string // the folder to write the embedded files to
}

func main() {
	var o options
	flag.StringVar(&o.root, "root", "", "the checkout whose z-nile/ engine is packed")
	flag.StringVar(&o.sum, "sum", "", "lune.sum, the pinned digests")
	flag.StringVar(&o.goos, "goos", "", "the target's GOOS (linux or darwin)")
	flag.StringVar(&o.goarch, "goarch", "", "the target's GOARCH (amd64 or arm64)")
	flag.StringVar(&o.lune, "lune", "", "a Lune binary, for a platform whose lune.sum entry is a bin")
	flag.StringVar(&o.zip, "zip", "", "a Lune release zip, for a platform whose lune.sum entry is a zip")
	flag.StringVar(&o.out, "out", "", "the folder to write lune, engine.tar and meta to")
	flag.Parse()
	if o.root == "" || o.sum == "" || o.goos == "" || o.goarch == "" || o.out == "" {
		fmt.Fprintln(os.Stderr, "usage: znpack -root <checkout> -sum <lune.sum> -goos <os> -goarch <arch> (-lune <binary> | -zip <zip>) -out <folder>")
		os.Exit(2)
	}
	if err := build(o, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "znpack:", err)
		os.Exit(1)
	}
}

// build verifies the Lune and writes the embedded files; on any error it writes nothing. It says on log when the packed
// folders have uncommitted edits.
func build(o options, log io.Writer) error {
	platform, err := payload.Platform(o.goos, o.goarch)
	if err != nil {
		return err
	}
	text, err := os.ReadFile(o.sum)
	if err != nil {
		return err
	}
	sums, err := payload.ParseSum(string(text))
	if err != nil {
		return err
	}
	entry, ok := sums[platform]
	if !ok {
		return fmt.Errorf("lune.sum pins no Lune for %s", platform)
	}
	src := o.lune
	if entry.Kind == "zip" {
		src = o.zip
	}
	if src == "" {
		flagName := "-lune <a Lune binary>"
		if entry.Kind == "zip" {
			flagName = "-zip <" + entry.Name + ">"
		}
		return fmt.Errorf("no Lune supplied for %s: pass %s (sha256 %s)", platform, flagName, entry.SHA)
	}
	data, err := os.ReadFile(src)
	if err != nil {
		return err
	}
	lune, err := entry.Lune(data)
	if err != nil {
		return err
	}
	var tarBuf bytes.Buffer
	dirty, err := payload.Pack(o.root, enginePaths, &tarBuf)
	if err != nil {
		return err
	}
	meta := "kind " + entry.Kind + "\n"
	if dirty {
		meta += "dirty 1\n"
		fmt.Fprintln(log, "znpack: the engine folders have uncommitted changes; this build is marked dirty (zn version says so)")
	}
	if err := os.MkdirAll(o.out, 0o755); err != nil {
		return err
	}
	for name, body := range map[string][]byte{"lune": lune, "engine.tar": tarBuf.Bytes(), "meta": []byte(meta)} {
		if err := os.WriteFile(filepath.Join(o.out, name), body, 0o644); err != nil {
			return err
		}
	}
	return nil
}
