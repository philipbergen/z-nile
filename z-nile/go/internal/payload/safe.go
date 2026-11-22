package payload

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"
)

// currentUID and ownerOf are the seams the ownership rule is tested through: a test cannot make a file another user's
// without root, so it swaps these.
var currentUID = func() int { return os.Getuid() }

var ownerOf = func(fi os.FileInfo) (int, bool) {
	st, ok := fi.Sys().(*syscall.Stat_t)
	if !ok {
		return 0, false
	}
	return int(st.Uid), true
}

// CacheFolder is where the payload is extracted: <base>/zn.
func CacheFolder(env []string) (string, error) {
	get := func(k string) string {
		for _, e := range env {
			if v, ok := strings.CutPrefix(e, k+"="); ok {
				return v
			}
		}
		return ""
	}
	if v := get("ZN_CACHE"); v != "" {
		if !filepath.IsAbs(v) {
			return "", fmt.Errorf("ZN_CACHE is %q: it must be an absolute path", v)
		}
		return filepath.Join(v, "zn"), nil
	}
	if v := get("XDG_CACHE_HOME"); filepath.IsAbs(v) {
		return filepath.Join(v, "zn"), nil
	}
	if h := get("HOME"); filepath.IsAbs(h) {
		return filepath.Join(h, ".cache", "zn"), nil
	}
	return "", fmt.Errorf("no cache folder: set ZN_CACHE to an absolute path (HOME is not set)")
}
