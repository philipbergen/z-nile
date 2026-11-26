//go:build linux

package main

import "syscall"

// getsid is the session of pid: the standard library has no Getsid on Linux, so the raw call.
func getsid(pid int) (int, error) {
	sid, _, e := syscall.RawSyscall(syscall.SYS_GETSID, uintptr(pid), 0, 0)
	if e != 0 {
		return 0, e
	}
	return int(sid), nil
}
