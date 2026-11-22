package wire

// SetPause replaces the wait between dial attempts and returns a function that puts the real one back. A test
// that uses it must not run in parallel with another that dials.
func SetPause(f func()) (restore func()) {
	old := pause
	pause = f
	return func() { pause = old }
}
