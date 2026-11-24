package web

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"regexp"
	"strings"
	"syscall"
)

// maxUnits is the largest units file the daemon reads (the real one is a few hundred KB).
const maxUnits = 4 << 20

// The units index is written by the engine's board refresh (units.json); these types are the shape the daemon passes on, so a
// field the file holds beyond them is dropped and a file of another shape is reported, not served. The daemon reads no ticket
// file and decides nothing: it validates and serves.
type unitPart struct {
	Heading string `json:"heading"`
	Text    string `json:"text"`
}
type unit struct {
	ID        string       `json:"id"`
	Kind      string       `json:"kind"`
	Title     string       `json:"title"`
	Project   string       `json:"project"`
	State     string       `json:"state"`
	Tributary string       `json:"tributary"`
	Themes    list[string] `json:"themes"`
	Raft      string       `json:"raft"`
	Members   list[string] `json:"members"`
	DependsOn list[string] `json:"depends_on"`
	// only an open unit carries a preview, only a withdrawn stub a day and a subject; each is left out of the answer when empty
	Problem  string         `json:"problem,omitempty"`
	Solution string         `json:"solution,omitempty"`
	Design   list[unitPart] `json:"design,omitempty"`
	Clipped  bool           `json:"clipped,omitempty"`
	When     string         `json:"when,omitempty"`
	Subject  string         `json:"subject,omitempty"`
}
type unitFacts struct {
	Version      int        `json:"version"`
	At           float64    `json:"at"`
	Commit       string     `json:"commit"`
	Sig          string     `json:"sig"`
	WithdrawnCut int        `json:"withdrawn_cut"`
	Dropped      int        `json:"dropped"` // units of an unknown kind, state or id shape, left out and counted here
	Units        list[unit] `json:"units"`
}

// unitsView is the whole of /api/units: the facts, or why there are none. It never holds a path.
type unitsView struct {
	State string     `json:"state"` // ok, absent or unreadable
	Why   string     `json:"why,omitempty"`
	Facts *unitFacts `json:"facts"`
}

const unitsAbsentWhy = "No units index has been written yet. It is written when the board is rebuilt (./zn sync, or ./zn board); this page updates by itself."
const unitsRefresh = "run ./zn board to write it again"

var (
	unitIDShape = regexp.MustCompile(`^(?:[cfd]|R)[0-9]{4}$`)
	unitStates  = map[string]bool{"backlog": true, "active": true, "done": true, "closed": true, "retired": true, "withdrawn": true}
	unitKinds   = map[string]bool{"ticket": true, "raft": true}
)

func unitsUnreadable(why string) unitsView { return unitsView{State: "unreadable", Why: why} }

// readUnits reads the index: a regular file of its own (never a link), at most maxUnits, version 1, with a units list. The second
// result is the entity tag of the bytes read ("" when there is no index to tag).
func (h *Handler) readUnits() (unitsView, string) {
	if h.UnitsPath == "" {
		return unitsView{State: "absent", Why: unitsAbsentWhy}, ""
	}
	if _, err := os.Lstat(h.UnitsPath); os.IsNotExist(err) {
		return unitsView{State: "absent", Why: unitsAbsentWhy}, ""
	}
	f, err := os.OpenFile(h.UnitsPath, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return unitsUnreadable("the units index cannot be opened (a link or no permission); " + unitsRefresh), ""
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil || !st.Mode().IsRegular() {
		return unitsUnreadable("the units index is not a regular file; " + unitsRefresh), ""
	}
	if st.Size() > maxUnits {
		return unitsUnreadable(fmt.Sprintf("the units index is over %d MiB; %s", maxUnits>>20, unitsRefresh)), ""
	}
	b, err := io.ReadAll(io.LimitReader(f, maxUnits+1))
	if err != nil || len(b) > maxUnits {
		return unitsUnreadable("the units index cannot be read; " + unitsRefresh), ""
	}
	var raw struct {
		Version int              `json:"version"`
		Units   *json.RawMessage `json:"units"`
	}
	if err := json.Unmarshal(b, &raw); err != nil {
		return unitsUnreadable("the units index is not valid JSON; " + unitsRefresh), ""
	}
	if raw.Version != 1 {
		return unitsUnreadable(fmt.Sprintf("the units index is version %d and this daemon reads version 1; update ./zn and %s", raw.Version, unitsRefresh)), ""
	}
	if raw.Units == nil {
		return unitsUnreadable("the units index has no units list; " + unitsRefresh), ""
	}
	var fs unitFacts
	if err := json.Unmarshal(b, &fs); err != nil {
		return unitsUnreadable("the units index has an unexpected shape; " + unitsRefresh), ""
	}
	kept := make(list[unit], 0, len(fs.Units))
	for _, u := range fs.Units {
		if unitKinds[u.Kind] && unitStates[u.State] && unitIDShape.MatchString(u.ID) {
			kept = append(kept, u)
		} else {
			fs.Dropped++
		}
	}
	fs.Units = kept
	sum := sha256.Sum256(b)
	return unitsView{State: "ok", Facts: &fs}, `"` + hex.EncodeToString(sum[:16]) + `"`
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

// units answers GET /api/units. It reads and reports; nothing here accepts input. A page that holds the tag of the bytes it has is
// told "not modified" and nothing is sent again.
func (h *Handler) units(w http.ResponseWriter, r *http.Request) {
	view, tag := h.readUnits()
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
