//go:build darwin

package fxtree

import "testing"

// On macOS the clone path itself must work: Copy falls back to cp silently, so a broken syscall would pass every other test
// and bring back one file event per file (c0179).
func TestCloneSucceedsOnAPFS(t *testing.T) {
	t.Parallel()
	src, dst, file := makeTree(t)
	if err := clone(src, dst); err != nil {
		t.Fatalf("clonefileat failed (Copy would silently fall back to cp): %v", err)
	}
	checkIndependentCopy(t, dst, file)
}
