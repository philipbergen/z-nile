package web_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"testing"
	"time"
)

// f0437 step 5: the themes overview's data. The engine writes themes.json (the board refresh, `./zn board`); the daemon
// serves it at GET /api/themes, validated, and never records or accepts anything.

const goodThemes = `{"version":1,"at":1700000100.5,"live":true,"approvalsAt":1700000000,"approvalsScope":"R0002","commit":"abc1234","themes":[
 {"id":"alpha","project":"p","title":"alpha","purpose":"first theme",
  "counts":{"done":3,"flight":2,"approval":1,"owner":1,"open":4},
  "workers":["claude w1","kimi w2"],
  "units":[{"id":"R0001","title":"Raft one","stage":"code","phase":"flight","holder":"claude w1","since":1699990000,"ids":["R0001","c0001"]},
           {"id":"c0180","title":"Taken","stage":"design","phase":"claimed","holder":"","claimedAt":"2026-10-31","ids":["c0180"]},
           {"id":"c0004","title":"Blocked","stage":"idea","phase":"owner","holder":""}],
  "secret":"never served"},
 {"id":"gamma","project":"p","title":"gamma","purpose":"","counts":{"done":0,"flight":0,"approval":0,"owner":0,"open":0},"workers":[],"units":[]}]}`

func writeThemes(t *testing.T, text string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "themes.json")
	if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func themesOf(t *testing.T, r *rig) map[string]any {
	t.Helper()
	resp := r.get("/api/themes", r.host, "")
	if resp.StatusCode != 200 || !strings.HasPrefix(resp.Header.Get("Content-Type"), "application/json") {
		t.Fatalf("status %d type %q", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(readAll(resp)), &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestThemesAbsentNamesTheCommand(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.ThemesPath = filepath.Join(t.TempDir(), "themes.json")
	got := themesOf(t, r)
	if got["state"] != "absent" || got["facts"] != nil {
		t.Fatalf("got %v", got)
	}
	if why, _ := got["why"].(string); !strings.Contains(why, "./zn board") || strings.Contains(why, r.h.ThemesPath) {
		t.Fatalf("the reason must name the command and no path: %q", why)
	}
}

func TestThemesServesTheFactsAndOnlyTheKnownFields(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.ThemesPath = writeThemes(t, goodThemes)
	got := themesOf(t, r)
	if got["state"] != "ok" {
		t.Fatalf("got %v", got)
	}
	facts := got["facts"].(map[string]any)
	themes := facts["themes"].([]any)
	if len(themes) != 2 || themes[0].(map[string]any)["id"] != "alpha" || themes[1].(map[string]any)["id"] != "gamma" {
		t.Fatalf("themes keep their order: %v", themes)
	}
	a := themes[0].(map[string]any)
	if _, has := a["secret"]; has {
		t.Error("an unknown field was passed through")
	}
	// exactly the known keys: a field the daemon adds of its own (a path, a host) must fail here
	keys := func(m map[string]any) string {
		var ks []string
		for k := range m {
			ks = append(ks, k)
		}
		sort.Strings(ks)
		return strings.Join(ks, ",")
	}
	if got := keys(a); got != "counts,id,project,purpose,title,units,workers" {
		t.Errorf("theme keys %s", got)
	}
	if got := keys(a["units"].([]any)[0].(map[string]any)); got != "holder,id,ids,phase,since,stage,title" {
		t.Errorf("unit keys %s", got)
	}
	if got := keys(facts); got != "approvalsAt,approvalsScope,at,commit,dropped,live,themes,version" {
		t.Errorf("facts keys %s", got)
	}
	counts := a["counts"].(map[string]any)
	if counts["done"] != float64(3) || counts["approval"] != float64(1) || counts["open"] != float64(4) {
		t.Errorf("counts %v", counts)
	}
	if ws := a["workers"].([]any); len(ws) != 2 || ws[0] != "claude w1" {
		t.Errorf("workers %v", ws)
	}
	us := a["units"].([]any)
	if len(us) != 3 || us[0].(map[string]any)["stage"] != "code" || us[0].(map[string]any)["since"] != float64(1699990000) {
		t.Errorf("units %v", us)
	}
	if c := us[1].(map[string]any); c["claimedAt"] != "2026-10-31" || c["phase"] != "claimed" {
		t.Errorf("a claimed unit keeps its day: %v", c)
	}
	if ids := us[0].(map[string]any)["ids"].([]any); len(ids) != 2 || ids[1] != "c0001" {
		t.Errorf("a unit carries its members' ids: %v", ids)
	}
	if facts["commit"] != "abc1234" {
		t.Errorf("the commit the facts were read at is served: %v", facts["commit"])
	}
	if facts["live"] != true || facts["approvalsScope"] != "R0002" || facts["approvalsAt"] != float64(1700000000) {
		t.Errorf("provenance %v", facts)
	}
}

func TestThemesUnreadableFileIsNamedNotServed(t *testing.T) {
	for name, text := range map[string]string{"not json": "{", "wrong version": `{"version":2,"themes":[]}`, "no themes": `{"version":1}`, "wrong shape": `{"version":1,"themes":{"a":1}}`} {
		r := newRig(t, "", 0)
		r.h.ThemesPath = writeThemes(t, text)
		got := themesOf(t, r)
		if got["state"] != "unreadable" || got["facts"] != nil {
			t.Errorf("%s: got %v", name, got)
		}
		if why, _ := got["why"].(string); why == "" || strings.Contains(why, r.h.ThemesPath) {
			t.Errorf("%s: reason %q", name, why)
		}
	}
}

func TestThemesRefusesALinkAndAHugeFile(t *testing.T) {
	r := newRig(t, "", 0)
	dir := t.TempDir()
	real := filepath.Join(dir, "real.json")
	os.WriteFile(real, []byte(goodThemes), 0o644)
	link := filepath.Join(dir, "themes.json")
	if err := os.Symlink(real, link); err != nil {
		t.Skip("no symlinks")
	}
	r.h.ThemesPath = link
	if got := themesOf(t, r); got["state"] != "unreadable" {
		t.Errorf("a symlink was followed: %v", got)
	}
	big := filepath.Join(dir, "big.json")
	os.WriteFile(big, []byte(`{"version":1,"themes":[],"pad":"`+strings.Repeat("x", 9<<20)+`"}`), 0o644)
	r.h.ThemesPath = big
	if got := themesOf(t, r); got["state"] != "unreadable" {
		t.Errorf("a file over the cap was read: %v", got)
	}
}

func TestThemesFifoDoesNotHang(t *testing.T) {
	r := newRig(t, "", 0)
	p := filepath.Join(t.TempDir(), "themes.json")
	if err := syscall.Mkfifo(p, 0o644); err != nil {
		t.Skip("no fifo")
	}
	r.h.ThemesPath = p
	done := make(chan map[string]any, 1)
	go func() { done <- themesOf(t, r) }()
	select {
	case got := <-done:
		if got["state"] != "unreadable" {
			t.Errorf("got %v", got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("the request hung on a named pipe")
	}
}

func TestThemesIsSameOriginGetOnly(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.ThemesPath = writeThemes(t, goodThemes)
	if resp := r.get("/api/themes", "evil.example:80", ""); resp.StatusCode != 403 {
		t.Errorf("wrong host: %d", resp.StatusCode)
	}
	if resp := r.get("/api/themes", r.host, "http://evil.example"); resp.StatusCode != 403 {
		t.Errorf("wrong origin: %d", resp.StatusCode)
	}
	for _, m := range []string{"POST", "PUT", "PATCH", "DELETE"} {
		req := httptest.NewRequest(m, "/api/themes", strings.NewReader(`{"unit":"c0001"}`))
		req.Host = r.host
		rec := httptest.NewRecorder()
		r.h.ServeHTTP(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Errorf("%s answered %d, want 405", m, rec.Code)
		}
	}
}

// Lune's JSON encoder writes an empty table as {}, so the engine's file holds {} where a list is empty.
func TestThemesReadsTheEnginesEmptyLists(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.ThemesPath = writeThemes(t, `{"version":1,"at":1,"live":false,"approvalsScope":"","themes":[{"id":"a","project":"p","title":"a","purpose":"x","counts":{"done":0,"flight":0,"approval":0,"owner":0,"open":0},"workers":{},"units":{}}]}`)
	got := themesOf(t, r)
	if got["state"] != "ok" {
		t.Fatalf("got %v", got)
	}
	a := got["facts"].(map[string]any)["themes"].([]any)[0].(map[string]any)
	if ws, ok := a["workers"].([]any); !ok || len(ws) != 0 {
		t.Errorf("workers %v", a["workers"])
	}
	r.h.ThemesPath = writeThemes(t, `{"version":1,"at":1,"live":true,"approvalsScope":"","themes":{}}`)
	if got := themesOf(t, r); got["state"] != "ok" {
		t.Errorf("an empty themes list was refused: %v", got)
	}
	r.h.ThemesPath = writeThemes(t, `{"version":1,"at":1,"live":true,"approvalsScope":"","themes":{"a":1}}`)
	if got := themesOf(t, r); got["state"] != "unreadable" {
		t.Errorf("an object with keys is not a list: %v", got)
	}
}

// themesWith puts one list field in the given shape (the others valid), at its own depth of the themes file.
func themesWith(field, val string) string {
	workers, units, themes := "[]", "[]", "[{"
	switch field {
	case "workers":
		workers = val
	case "units":
		units = val
	}
	row := `{"id":"a","project":"p","title":"a","purpose":"x","counts":{"done":0,"flight":0,"approval":0,"owner":0,"open":0},"workers":` + workers + `,"units":` + units + `}`
	themes = "[" + row + "]"
	if field == "themes" {
		themes = val
	}
	return `{"version":1,"at":1,"live":true,"approvalsScope":"","themes":` + themes + `}`
}

// Every list of the themes file (themes, workers, units) takes the engine's `{}` as an empty list and refuses a non-empty object.
func TestEveryThemesListTakesAnEmptyObjectAndRefusesAFullOne(t *testing.T) {
	for _, field := range []string{"themes", "workers", "units"} {
		t.Run(field+" empty object", func(t *testing.T) {
			r := newRig(t, "", 0)
			r.h.ThemesPath = writeThemes(t, themesWith(field, "{}"))
			if got := themesOf(t, r); got["state"] != "ok" {
				t.Fatalf("got %v", got)
			}
		})
		t.Run(field+" full object", func(t *testing.T) {
			r := newRig(t, "", 0)
			r.h.ThemesPath = writeThemes(t, themesWith(field, `{"a":1}`))
			got := themesOf(t, r)
			if got["state"] != "unreadable" || !strings.Contains(got["why"].(string), "unexpected shape") {
				t.Fatalf("got %v", got)
			}
		})
	}
}

// A list key missing from the file (the only way a list is nil) is served as [], never null.
func TestThemesMissingListsAreServedAsEmptyArrays(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.ThemesPath = writeThemes(t, `{"version":1,"at":1,"live":true,"approvalsScope":"","themes":[{"id":"a","project":"p","title":"a","purpose":"x","counts":{"done":0,"flight":0,"approval":0,"owner":0,"open":0}}]}`)
	body := readAll(r.get("/api/themes", r.host, ""))
	for _, want := range []string{`"workers":[]`, `"units":[]`} {
		if !strings.Contains(body, want) {
			t.Errorf("%s missing in %s", want, body)
		}
	}
	if strings.Contains(body, `"workers":null`) || strings.Contains(body, `"units":null`) || strings.Contains(body, `"themes":null`) {
		t.Errorf("a missing list leaked as null: %s", body)
	}
}
