//go:build darwin || linux || freebsd || netbsd || openbsd

package main

import (
	"syscall"
	"unsafe"
)

// The terminal calls zn needs to run the engine as the terminal's foreground group (f0428 step 4, round 5), on the
// standard library alone: whether a descriptor is a terminal, and its foreground process group.

// isTerminal says fd is a terminal.
func isTerminal(fd int) bool {
	var t syscall.Termios
	_, _, e := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), uintptr(ioctlGetTermios), uintptr(unsafe.Pointer(&t)))
	return e == 0
}

// tcgetpgrp is the foreground process group of the terminal fd.
func tcgetpgrp(fd int) (int, error) {
	var pg int32
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), uintptr(syscall.TIOCGPGRP), uintptr(unsafe.Pointer(&pg))); e != 0 {
		return 0, e
	}
	return int(pg), nil
}

// tcsetpgrp makes pg the foreground process group of the terminal fd. The caller ignores SIGTTOU around it: a process
// in a background group that sets the foreground group is otherwise stopped by it.
func tcsetpgrp(fd, pg int) error {
	p := int32(pg)
	if _, _, e := syscall.Syscall(syscall.SYS_IOCTL, uintptr(fd), uintptr(syscall.TIOCSPGRP), uintptr(unsafe.Pointer(&p))); e != 0 {
		return e
	}
	return nil
}
