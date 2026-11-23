package web_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

// f0437 step 5: the themes overview's data. The engine writes themes.json (the board refresh, `./zn board`); the daemon
// serves it at GET /api/themes, validated, and never records or accepts anything.

const goodThemes = `{"version":1,"at":1700000100.5,"live":true,"approvalsAt":1700000000,"approvalsScope":"R0002","themes":[
 {"id":"alpha","project":"p","title":"alpha","purpose":"first theme",
  "counts":{"done":3,"flight":2,"approval":1,"owner":1,"open":4},
  "workers":["claude w1","kimi w2"],
  "units":[{"id":"R0001","title":"Raft one","stage":"code","phase":"flight","holder":"claude w1","since":1699990000},
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
	counts := a["counts"].(map[string]any)
	if counts["done"] != float64(3) || counts["approval"] != float64(1) || counts["open"] != float64(4) {
		t.Errorf("counts %v", counts)
	}
	if ws := a["workers"].([]any); len(ws) != 2 || ws[0] != "claude w1" {
		t.Errorf("workers %v", ws)
	}
	us := a["units"].([]any)
	if len(us) != 2 || us[0].(map[string]any)["stage"] != "code" || us[0].(map[string]any)["since"] != float64(1699990000) {
		t.Errorf("units %v", us)
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
