// Package fxtree copies fixture folders for tests cheaply (c0179): on APFS one copy-on-write clone of the whole tree, which
// the system logs as two file events however many files the tree holds (cp -R logs one per file), else cp -Rp. It is for test
// code only and holds no state.
package fxtree

import (
	"context"
	"fmt"
	"os/exec"
	"time"
)

// Copy makes dst, which must not exist, a copy of the tree src with its modes and links, bounded like every process a test
// starts. The copy is independent of src: a write to either never shows in the other.
func Copy(src, dst string) error {
	if clone(src, dst) == nil { // a failed clone leaves no dst
		return nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	if out, err := exec.CommandContext(ctx, "cp", "-Rp", src, dst).CombinedOutput(); err != nil {
		return fmt.Errorf("cp %s %s: %v: %s", src, dst, err, out)
	}
	return nil
}
