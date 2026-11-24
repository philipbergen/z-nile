//go:build !darwin

package fxtree

import "errors"

// clone is only for APFS (clone_darwin.go): elsewhere the caller copies.
func clone(src, dst string) error { return errors.New("no copy-on-write clone on this system") }
