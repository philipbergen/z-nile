package web

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"runtime/debug"
	"strings"
)

// BuildID names this build of the daemon. It is in every entity tag, so a page that outlives a daemon upgrade asks again.
var BuildID = buildID()

func buildID() string {
	h := sha256.New()
	if bi, ok := debug.ReadBuildInfo(); ok {
		fmt.Fprint(h, bi.Main.Version)
		for _, s := range bi.Settings {
			if strings.HasPrefix(s.Key, "vcs.") {
				fmt.Fprint(h, s.Key, s.Value)
			}
		}
	}
	if exe, err := os.Executable(); err == nil {
		if st, err := os.Stat(exe); err == nil {
			fmt.Fprint(h, st.Size(), st.ModTime().UnixNano())
		}
	}
	return hex.EncodeToString(h.Sum(nil))[:12]
}

// tagOf is the entity tag of the bytes a facts route read: the build and a hash of the file.
func tagOf(b []byte) string {
	sum := sha256.Sum256(b)
	return `"` + BuildID + "-" + hex.EncodeToString(sum[:16]) + `"`
}

// etagMatches reports whether an If-None-Match header names tag (any entry of a list, weak or strong).
func etagMatches(header, tag string) bool {
	for _, p := range strings.Split(header, ",") {
		if strings.TrimPrefix(strings.TrimSpace(p), "W/") == tag {
			return true
		}
	}
	return false
}

// serveFacts answers a facts route: the view as JSON, with its tag, or 304 to a page that holds the tag. A view with no tag (no file,
// or one that cannot be read) is never answered with 304.
func serveFacts(w http.ResponseWriter, r *http.Request, view any, tag string) {
	w.Header().Set("Content-Type", "application/json")
	if tag != "" {
		w.Header().Set("ETag", tag)
		if etagMatches(r.Header.Get("If-None-Match"), tag) {
			w.WriteHeader(http.StatusNotModified)
			return
		}
	}
	json.NewEncoder(w).Encode(view)
}
