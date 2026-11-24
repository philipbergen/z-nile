//go:build !darwin

package fxtree

// setImmutable does nothing off macOS: there the folders' modes are the whole of Freeze.
func setImmutable(dir string, on bool) error { return nil }
