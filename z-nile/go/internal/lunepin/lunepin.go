// Package lunepin finds the Lune that zn pins (cmd/zn/lune.sum) and runs a program bounded (stub: the tests come first).
package lunepin

import (
	"context"
	"os/exec"
	"time"
)

// versionTimeout bounds the one probe Find may run.
var versionTimeout = 10 * time.Second

// Platform is this machine's platform (stub).
func Platform() string { return "" }

// Find is the pinned Lune (stub).
func Find(sum, pathList, home string) (string, bool) { return "", false }

// Command is a bounded command (stub).
func Command(ctx context.Context, name string, args ...string) *exec.Cmd {
	return exec.CommandContext(ctx, name, args...)
}
