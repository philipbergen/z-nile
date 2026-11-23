package web

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"syscall"
)

// The themes facts are written by the engine's board refresh (themes.json); these types are the shape the daemon passes on,
// so a field the file holds beyond them is dropped and a file of another shape is reported, not served. The daemon reads
// no ticket file and decides nothing: it validates and serves.
type themeCounts struct {
	Done     int `json:"done"`
	Flight   int `json:"flight"`
	Approval int `json:"approval"`
	Owner    int `json:"owner"`
	Open     int `json:"open"`
}
type themeUnit struct {
	ID     string   `json:"id"`
	Title  string   `json:"title"`
	Stage  string   `json:"stage"`
	Phase  string   `json:"phase"`
	Holder string   `json:"holder"`
	Since  *float64 `json:"since,omitempty"`
}
type themeRow struct {
	ID      string          `json:"id"`
	Project string          `json:"project"`
	Title   string          `json:"title"`
	Purpose string          `json:"purpose"`
	Counts  themeCounts     `json:"counts"`
	Workers list[string]    `json:"workers"`
	Units   list[themeUnit] `json:"units"`
}
type themeFacts struct {
	Version        int            `json:"version"`
	At             float64        `json:"at"`
	Live           bool           `json:"live"`
	ApprovalsAt    *float64       `json:"approvalsAt,omitempty"`
	ApprovalsScope string         `json:"approvalsScope"`
	Themes         list[themeRow] `json:"themes"`
}

// themesView is the whole of /api/themes: the facts, or why there are none. It never holds a path.
type themesView struct {
	State string      `json:"state"` // ok, absent or unreadable
	Why   string      `json:"why,omitempty"`
	Facts *themeFacts `json:"facts"`
}

const themesAbsentWhy = "No theme facts have been written yet. They are written when the board is rebuilt (./zn sync, or ./zn board); this page updates by itself."
const themesRefresh = "run ./zn board to write them again"

func themesUnreadable(why string) themesView { return themesView{State: "unreadable", Why: why} }

// readThemes reads the facts file: a regular file of its own (never a link), at most maxFacts, version 1, with a themes list.
func (h *Handler) readThemes() themesView {
	if h.ThemesPath == "" {
		return themesView{State: "absent", Why: themesAbsentWhy}
	}
	if _, err := os.Lstat(h.ThemesPath); os.IsNotExist(err) {
		return themesView{State: "absent", Why: themesAbsentWhy}
	}
	f, err := os.OpenFile(h.ThemesPath, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return themesUnreadable("the theme facts file cannot be opened (a link or no permission); " + themesRefresh)
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil || !st.Mode().IsRegular() {
		return themesUnreadable("the theme facts are not a regular file; " + themesRefresh)
	}
	if st.Size() > maxFacts {
		return themesUnreadable(fmt.Sprintf("the theme facts are over %d MiB; %s", maxFacts>>20, themesRefresh))
	}
	b, err := io.ReadAll(io.LimitReader(f, maxFacts+1))
	if err != nil || len(b) > maxFacts {
		return themesUnreadable("the theme facts cannot be read; " + themesRefresh)
	}
	var raw struct {
		Version int              `json:"version"`
		Themes  *json.RawMessage `json:"themes"`
	}
	if err := json.Unmarshal(b, &raw); err != nil {
		return themesUnreadable("the theme facts are not valid JSON; " + themesRefresh)
	}
	if raw.Version != 1 {
		return themesUnreadable(fmt.Sprintf("the theme facts are version %d and this daemon reads version 1; update ./zn and %s", raw.Version, themesRefresh))
	}
	if raw.Themes == nil {
		return themesUnreadable("the theme facts have no themes list; " + themesRefresh)
	}
	var fs themeFacts
	if err := json.Unmarshal(b, &fs); err != nil {
		return themesUnreadable("the theme facts have an unexpected shape; " + themesRefresh)
	}
	if fs.Themes == nil {
		fs.Themes = list[themeRow]{}
	}
	for i := range fs.Themes {
		if fs.Themes[i].Workers == nil {
			fs.Themes[i].Workers = list[string]{}
		}
		if fs.Themes[i].Units == nil {
			fs.Themes[i].Units = list[themeUnit]{}
		}
	}
	return themesView{State: "ok", Facts: &fs}
}

// themes answers GET /api/themes. It reads and reports; nothing here accepts input.
func (h *Handler) themes(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(h.readThemes())
}
