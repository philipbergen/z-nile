//go:build darwin || freebsd || netbsd || openbsd

package main

import "syscall"

// ioctlGetTermios reads a terminal's settings (a call that fails on anything but a terminal).
const ioctlGetTermios = syscall.TIOCGETA
