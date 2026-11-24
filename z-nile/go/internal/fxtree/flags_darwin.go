//go:build darwin

package fxtree

import (
	"context"
	"os/exec"
	"time"
)

// setImmutable sets or clears the user-immutable flag on every entry under dir (chflags -R), bounded.
func setImmutable(dir string, on bool) error {
	flag := "nouchg"
	if on {
		flag = "uchg"
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	return exec.CommandContext(ctx, "/usr/bin/chflags", "-R", flag, dir).Run()
}
