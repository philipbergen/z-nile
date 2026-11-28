//go:build darwin

package fxtree

import (
	"syscall"
	"unsafe"
)

// sysClonefileat is clonefileat(2) in <sys/syscall.h> (libc's clonefile is clonefileat with both folders AT_FDCWD).
const sysClonefileat = 462

// atFDCWD is AT_FDCWD on macOS, as a syscall argument.
const atFDCWD = -2

// clone makes dst a copy-on-write clone of the tree src in one system call (APFS): the file system makes one
// directory entry for the whole tree instead of one per file, so the copy costs two file events where cp -R costs one per
// file (c0179, measured). dst must not exist. It fails where the volume cannot clone, and the caller then copies.
func clone(src, dst string) error {
	s, err := syscall.BytePtrFromString(src)
	if err != nil {
		return err
	}
	d, err := syscall.BytePtrFromString(dst)
	if err != nil {
		return err
	}
	cwd := atFDCWD
	if _, _, e := syscall.Syscall6(sysClonefileat, uintptr(cwd), uintptr(unsafe.Pointer(s)), uintptr(cwd), uintptr(unsafe.Pointer(d)), 0, 0); e != 0 {
		return e
	}
	return nil
}
