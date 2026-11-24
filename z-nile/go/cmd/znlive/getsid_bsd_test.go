//go:build darwin || freebsd || netbsd || openbsd

package main

import "syscall"

// getsid is the session of pid: the standard library has it on the BSDs (macOS), not on Linux.
func getsid(pid int) (int, error) { return syscall.Getsid(pid) }
