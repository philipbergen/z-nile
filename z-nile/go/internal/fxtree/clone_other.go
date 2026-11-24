//go:build !darwin

package fxtree

// clone is only for APFS (clone_darwin.go): elsewhere the caller copies.
func clone(src, dst string) error { return errNoClone }
