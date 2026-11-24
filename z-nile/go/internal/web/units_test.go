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

	"znile/internal/web"
)

// f0437 step 6, slice 2: the units index. The engine writes units.json (the board refresh); the daemon serves it at
// GET /api/units, validated, with an ETag so a page asks again for nothing when it has not changed. The daemon reads no ticket
// file: it validates and serves.

const goodUnits = `{"version":1,"at":1700000100,"commit":"abc1234","sig":"` + "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" + `","withdrawn_cut":0,"units":[
 {"id":"c0001","kind":"ticket","title":"Open one","project":"p","state":"backlog","tributary":"alpha","themes":["alpha"],"raft":"R0010","members":[],"depends_on":["c0003"],
  "problem":"The problem.","solution":"The solution.","problem_size":900,"solution_size":800,"design":[{"heading":"Part","text":"Text.","size":5000}],"clipped":true,"secret":"never served"},
 {"id":"c0003","kind":"ticket","title":"Done one","project":"p","state":"done","tributary":"earlier-work","themes":["earlier-work"],"raft":"","members":[],"depends_on":[]},
 {"id":"R0010","kind":"raft","title":"A raft","project":"p","state":"active","tributary":"alpha","themes":["alpha","beta"],"raft":"","members":["c0001"],"depends_on":[],"problem":"P","solution":"S","design":[]},
 {"id":"c0004","kind":"ticket","title":"Closed","project":"p","state":"closed","tributary":"unsorted","themes":["unsorted"],"raft":"","members":[],"depends_on":[]},
 {"id":"R0012","kind":"raft","title":"Retired","project":"p","state":"retired","tributary":"unsorted","themes":["unsorted"],"raft":"","members":[],"depends_on":[]},
 {"id":"c0261","kind":"ticket","title":"","project":"","state":"withdrawn","tributary":"","themes":[],"raft":"","members":[],"depends_on":[],"when":"2026-11-02","subject":"tracker: withdraw c0261 (met by #299)","fate":"withdrawn"}]}`

func writeUnits(t *testing.T, text string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "units.json")
	if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func unitsOf(t *testing.T, r *rig) map[string]any {
	t.Helper()
	resp := r.get("/api/units", r.host, "")
	if resp.StatusCode != 200 || !strings.HasPrefix(resp.Header.Get("Content-Type"), "application/json") {
		t.Fatalf("status %d type %q", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(readAll(resp)), &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func keysOf(m map[string]any) string {
	var ks []string
	for k := range m {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return strings.Join(ks, ",")
}

func TestUnitsAbsentNamesTheCommand(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.UnitsPath = filepath.Join(t.TempDir(), "units.json")
	got := unitsOf(t, r)
	if got["state"] != "absent" || got["facts"] != nil {
		t.Fatalf("got %v", got)
	}
	if why, _ := got["why"].(string); !strings.Contains(why, "./zn board") || strings.Contains(why, r.h.UnitsPath) {
		t.Fatalf("the reason must name the command and no path: %q", why)
	}
	r.h.UnitsPath = ""
	if got := unitsOf(t, r); got["state"] != "absent" {
		t.Fatalf("no path: %v", got)
	}
}

// The exact key set of every level: a field the daemon adds of its own (a path, a host) or one it passes by accident fails here.
func TestUnitsServesTheFactsAndExactlyTheKnownKeys(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.UnitsPath = writeUnits(t, goodUnits)
	got := unitsOf(t, r)
	if got["state"] != "ok" {
		t.Fatalf("got %v", got)
	}
	facts := got["facts"].(map[string]any)
	if k := keysOf(facts); k != "at,commit,dropped,sig,units,version,withdrawn_cut" {
		t.Errorf("facts keys %s", k)
	}
	units := facts["units"].([]any)
	if len(units) != 6 {
		t.Fatalf("units %v", units)
	}
	open := units[0].(map[string]any)
	if k := keysOf(open); k != "clipped,depends_on,design,id,kind,members,problem,problem_size,project,raft,solution,solution_size,state,themes,title,tributary" {
		t.Errorf("an open unit's keys %s", k)
	}
	if _, has := open["secret"]; has {
		t.Error("an unknown field was passed through")
	}
	if k := keysOf(units[1].(map[string]any)); k != "depends_on,id,kind,members,project,raft,state,themes,title,tributary" {
		t.Errorf("a done unit's keys %s", k)
	}
	stub := units[5].(map[string]any)
	if k := keysOf(stub); k != "depends_on,fate,id,kind,members,project,raft,state,subject,themes,title,tributary,when" {
		t.Errorf("a withdrawn stub's keys %s", k)
	}
	if stub["when"] != "2026-11-02" || stub["subject"] != "tracker: withdraw c0261 (met by #299)" || stub["state"] != "withdrawn" {
		t.Errorf("stub %v", stub)
	}
	if d := open["design"].([]any)[0].(map[string]any); keysOf(d) != "heading,size,text" || d["heading"] != "Part" {
		t.Errorf("design %v", d)
	}
	for _, st := range []string{"closed", "retired"} {
		found := false
		for _, u := range units {
			if u.(map[string]any)["state"] == st {
				found = true
			}
		}
		if !found {
			t.Errorf("state %s was dropped", st)
		}
	}
	if facts["sig"] != "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" || facts["commit"] != "abc1234" || facts["dropped"] != float64(0) {
		t.Errorf("provenance %v", facts)
	}
}

func TestUnitsUnreadableFileIsNamedNotServed(t *testing.T) {
	for name, text := range map[string]string{
		"not json":      "{",
		"wrong version": `{"version":2,"units":[]}`,
		"no units":      `{"version":1}`,
		"wrong shape":   `{"version":1,"units":{"a":1}}`,
	} {
		r := newRig(t, "", 0)
		r.h.UnitsPath = writeUnits(t, text)
		got := unitsOf(t, r)
		if got["state"] != "unreadable" || got["facts"] != nil {
			t.Errorf("%s: got %v", name, got)
		}
		if why, _ := got["why"].(string); why == "" || strings.Contains(why, r.h.UnitsPath) {
			t.Errorf("%s: reason %q", name, why)
		}
	}
}

func TestUnitsRefusesALinkAndAFileOverFourMiB(t *testing.T) {
	r := newRig(t, "", 0)
	dir := t.TempDir()
	real := filepath.Join(dir, "real.json")
	os.WriteFile(real, []byte(goodUnits), 0o644)
	link := filepath.Join(dir, "units.json")
	if err := os.Symlink(real, link); err != nil {
		t.Skip("no symlinks")
	}
	r.h.UnitsPath = link
	if got := unitsOf(t, r); got["state"] != "unreadable" {
		t.Errorf("a symlink was followed: %v", got)
	}
	big := filepath.Join(dir, "big.json")
	os.WriteFile(big, []byte(`{"version":1,"units":[],"pad":"`+strings.Repeat("x", 4<<20)+`"}`), 0o644)
	r.h.UnitsPath = big
	got := unitsOf(t, r)
	if got["state"] != "unreadable" || !strings.Contains(got["why"].(string), "4 MiB") {
		t.Errorf("a file over the cap was read, or the cap was not named: %v", got)
	}
}

func TestUnitsFifoDoesNotHang(t *testing.T) {
	r := newRig(t, "", 0)
	p := filepath.Join(t.TempDir(), "units.json")
	if err := syscall.Mkfifo(p, 0o644); err != nil {
		t.Skip("no fifo")
	}
	r.h.UnitsPath = p
	done := make(chan map[string]any, 1)
	go func() { done <- unitsOf(t, r) }()
	select {
	case got := <-done:
		if got["state"] != "unreadable" {
			t.Errorf("got %v", got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("the request hung on a named pipe")
	}
}

func TestUnitsIsSameOriginGetOnly(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.UnitsPath = writeUnits(t, goodUnits)
	if resp := r.get("/api/units", "evil.example:80", ""); resp.StatusCode != 403 {
		t.Errorf("wrong host: %d", resp.StatusCode)
	}
	if resp := r.get("/api/units", r.host, "http://evil.example"); resp.StatusCode != 403 {
		t.Errorf("wrong origin: %d", resp.StatusCode)
	}
	for _, m := range []string{"POST", "PUT", "PATCH", "DELETE"} {
		req := httptest.NewRequest(m, "/api/units", strings.NewReader(`{"unit":"c0001"}`))
		req.Host = r.host
		rec := httptest.NewRecorder()
		r.h.ServeHTTP(rec, req)
		if rec.Code != http.StatusMethodNotAllowed {
			t.Errorf("%s answered %d, want 405", m, rec.Code)
		}
	}
}

// Lune's JSON encoder writes an empty table as {}: every list of the units file takes it as empty and refuses a full object.
func TestUnitsReadsTheEnginesEmptyLists(t *testing.T) {
	unit := func(field, val string) string {
		lists := map[string]string{"themes": "[]", "members": "[]", "depends_on": "[]", "design": "[]"}
		lists[field] = val
		return `{"version":1,"at":1,"commit":"","sig":"s","withdrawn_cut":0,"units":[{"id":"c0001","kind":"ticket","title":"t","project":"p","state":"backlog","tributary":"a","themes":` + lists["themes"] +
			`,"raft":"","members":` + lists["members"] + `,"depends_on":` + lists["depends_on"] + `,"problem":"p","solution":"s","design":` + lists["design"] + `}]}`
	}
	for _, field := range []string{"themes", "members", "depends_on", "design"} {
		t.Run(field+" empty object", func(t *testing.T) {
			r := newRig(t, "", 0)
			r.h.UnitsPath = writeUnits(t, unit(field, "{}"))
			if got := unitsOf(t, r); got["state"] != "ok" {
				t.Fatalf("got %v", got)
			}
		})
		t.Run(field+" full object", func(t *testing.T) {
			r := newRig(t, "", 0)
			r.h.UnitsPath = writeUnits(t, unit(field, `{"a":1}`))
			got := unitsOf(t, r)
			if got["state"] != "unreadable" || !strings.Contains(got["why"].(string), "unexpected shape") {
				t.Fatalf("got %v", got)
			}
		})
	}
	r := newRig(t, "", 0)
	r.h.UnitsPath = writeUnits(t, `{"version":1,"at":1,"sig":"s","units":{}}`)
	got := unitsOf(t, r)
	if got["state"] != "ok" {
		t.Fatalf("an empty units list was refused: %v", got)
	}
	if body := readAll(r.get("/api/units", r.host, "")); !strings.Contains(body, `"units":[]`) || strings.Contains(body, "null") {
		t.Errorf("an empty list is [], never {} or null: %s", body)
	}
}

// An unknown kind or state is dropped from the served list and counted, never served and never the whole file refused.
func TestUnitsDropsUnknownKindsAndStatesAndCountsThem(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.UnitsPath = writeUnits(t, `{"version":1,"at":1,"sig":"s","units":[
 {"id":"c0001","kind":"ticket","title":"ok","project":"p","state":"backlog","tributary":"a","themes":[],"raft":"","members":[],"depends_on":[]},
 {"id":"c0002","kind":"widget","title":"bad kind","project":"p","state":"backlog","tributary":"a","themes":[],"raft":"","members":[],"depends_on":[]},
 {"id":"c0003","kind":"ticket","title":"bad state","project":"p","state":"lost","tributary":"a","themes":[],"raft":"","members":[],"depends_on":[]},
 {"id":"../x","kind":"ticket","title":"bad id","project":"p","state":"done","tributary":"a","themes":[],"raft":"","members":[],"depends_on":[]}]}`)
	got := unitsOf(t, r)["facts"].(map[string]any)
	units := got["units"].([]any)
	if len(units) != 1 || units[0].(map[string]any)["id"] != "c0001" {
		t.Errorf("units %v", units)
	}
	if got["dropped"] != float64(3) {
		t.Errorf("dropped %v", got["dropped"])
	}
}

func TestUnitsAnswersNotModifiedForTheSameFileAndNewForAChange(t *testing.T) {
	r := newRig(t, "", 0)
	p := writeUnits(t, goodUnits)
	r.h.UnitsPath = p
	first := r.get("/api/units", r.host, "")
	etag := first.Header.Get("ETag")
	if etag == "" || !strings.HasPrefix(etag, `"`) {
		t.Fatalf("no ETag: %q", etag)
	}
	ask := func(tag string) *http.Response {
		req, _ := http.NewRequest("GET", r.srv.URL+"/api/units", nil)
		req.Host = r.host
		if tag != "" {
			req.Header.Set("If-None-Match", tag)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() { resp.Body.Close() })
		return resp
	}
	same := ask(etag)
	if same.StatusCode != http.StatusNotModified || readAll(same) != "" {
		t.Fatalf("the same file answered %d", same.StatusCode)
	}
	if got := ask(`"other"`); got.StatusCode != 200 {
		t.Errorf("another tag answered %d", got.StatusCode)
	}
	if err := os.WriteFile(p, []byte(strings.Replace(goodUnits, "Open one", "Open two", 1)), 0o644); err != nil {
		t.Fatal(err)
	}
	changed := ask(etag)
	if changed.StatusCode != 200 || changed.Header.Get("ETag") == etag {
		t.Errorf("a changed file answered %d with tag %q", changed.StatusCode, changed.Header.Get("ETag"))
	}
	// an unreadable file is never answered with 304, whatever the page sends
	os.WriteFile(p, []byte("{"), 0o644)
	if got := ask(etag); got.StatusCode != 200 {
		t.Errorf("an unreadable file answered %d", got.StatusCode)
	}
}

// f0437 step 6 (F12): the one-time real-data proof. tests/chain/units-chain.sh writes the units index of the real tracker with
// the engine, this test serves it through the reader exactly as the daemon does, and the page's link code runs over what was
// served. Skipped unless ZN_REAL_UNITS names the file, so the gate never reads the real tracker.
func TestRealUnitsChain(t *testing.T) {
	in, out := os.Getenv("ZN_REAL_UNITS"), os.Getenv("ZN_REAL_UNITS_SERVED")
	if in == "" || out == "" {
		t.Skip("one-time real-data proof: set ZN_REAL_UNITS and ZN_REAL_UNITS_SERVED (tests/chain/units-chain.sh does)")
	}
	r := newRig(t, "", 0)
	r.h.UnitsPath = in
	body := readAll(r.get("/api/units", r.host, ""))
	var got struct {
		State string `json:"state"`
		Why   string `json:"why"`
		Facts struct {
			Dropped int `json:"dropped"`
			Units   []struct {
				ID    string `json:"id"`
				State string `json:"state"`
			} `json:"units"`
		} `json:"facts"`
	}
	if err := json.Unmarshal([]byte(body), &got); err != nil || got.State != "ok" {
		t.Fatalf("the real units were not served: %v %q %q", err, got.State, got.Why)
	}
	if got.Facts.Dropped != 0 {
		t.Fatalf("the reader dropped %d units of the real index", got.Facts.Dropped)
	}
	// what the engine wrote and what was served hold the same units: nothing is lost in the reader
	var raw struct {
		Units []struct {
			ID string `json:"id"`
		} `json:"units"`
	}
	b, err := os.ReadFile(in)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(b, &raw); err != nil || len(raw.Units) != len(got.Facts.Units) {
		t.Fatalf("the engine wrote %d units, the reader served %d (%v)", len(raw.Units), len(got.Facts.Units), err)
	}
	if err := os.WriteFile(out, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// The same proof for the theme facts the link rules read tributary names from: tests/chain/units-chain.sh serves the real
// themes.json through the reader and the page's code runs over what was served. Skipped unless ZN_REAL_THEMES names the file.
func TestRealThemesChain(t *testing.T) {
	in, out := os.Getenv("ZN_REAL_THEMES"), os.Getenv("ZN_REAL_THEMES_SERVED")
	if in == "" || out == "" {
		t.Skip("one-time real-data proof: set ZN_REAL_THEMES and ZN_REAL_THEMES_SERVED (tests/chain/units-chain.sh does)")
	}
	r := newRig(t, "", 0)
	r.h.ThemesPath = in
	body := readAll(r.get("/api/themes", r.host, ""))
	var got struct {
		State string `json:"state"`
		Why   string `json:"why"`
	}
	if err := json.Unmarshal([]byte(body), &got); err != nil || got.State != "ok" {
		t.Fatalf("the real themes were not served: %v %q %q", err, got.State, got.Why)
	}
	if err := os.WriteFile(out, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// Review F4: the count of what was left out starts at nothing and is the reader's own: a file that says "dropped": -3 hides no drop.
func TestUnitsDroppedIsTheReadersOwnCount(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.UnitsPath = writeUnits(t, `{"version":1,"at":1,"sig":"s","dropped":-3,"units":[
 {"id":"c0001","kind":"ticket","title":"ok","project":"p","state":"backlog","tributary":"a","themes":[],"raft":"","members":[],"depends_on":[]},
 {"id":"c0002","kind":"widget","title":"bad","project":"p","state":"backlog","tributary":"a","themes":[],"raft":"","members":[],"depends_on":[]}]}`)
	got := unitsOf(t, r)["facts"].(map[string]any)
	if got["dropped"] != float64(1) {
		t.Fatalf("dropped %v, want 1 (the file's own -3 is ignored)", got["dropped"])
	}
}

// Review F1: the reader is the second line of defence. Every field the page builds an address or a command from is shape-checked
// here too; what fails is dropped and counted.
func TestUnitsFieldsAreShapeCheckedAndWhatFailsIsCounted(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.UnitsPath = writeUnits(t, `{"version":1,"at":1,"sig":"s","units":[
 {"id":"R0010","kind":"raft","title":"t","project":"p","state":"backlog","tributary":"A B","themes":["Bad Name","alpha","javascript:alert(1)//"],"raft":"../x","members":["javascript:alert(1)//\"><x>","c0002"],"depends_on":["x","c0003"]},
 {"id":"c0261","kind":"ticket","title":"","project":"","state":"withdrawn","tributary":"","themes":[],"raft":"","members":[],"depends_on":[],"when":"d","subject":"s","fate":"renumbered","to":"<x>"}]}`)
	got := unitsOf(t, r)["facts"].(map[string]any)
	u := got["units"].([]any)[0].(map[string]any)
	if u["tributary"] != "" || u["raft"] != "" {
		t.Errorf("tributary %q raft %q", u["tributary"], u["raft"])
	}
	if th := u["themes"].([]any); len(th) != 1 || th[0] != "alpha" {
		t.Errorf("themes %v", th)
	}
	if m := u["members"].([]any); len(m) != 1 || m[0] != "c0002" {
		t.Errorf("members %v", m)
	}
	if d := u["depends_on"].([]any); len(d) != 1 || d[0] != "c0003" {
		t.Errorf("depends_on %v", d)
	}
	stub := got["units"].([]any)[1].(map[string]any)
	if _, has := stub["to"]; has {
		t.Errorf("a renumbered target that is no id was served: %v", stub["to"])
	}
	// themes 2, members 1, depends_on 1, raft 1, tributary 1, to 1
	if got["dropped"] != float64(7) {
		t.Errorf("dropped %v, want 7", got["dropped"])
	}
}

// Review F15: approvals, themes and units answer a matching If-None-Match with 304, and every tag carries the daemon's build id,
// so a page that outlives a daemon upgrade asks again.
func TestEveryFactsRouteAnswersNotModifiedAndTagsCarryTheBuildID(t *testing.T) {
	for _, route := range []string{"/api/approvals", "/api/themes", "/api/units"} {
		r := newRig(t, "", 0)
		r.h.FactsPath = writeFacts(t, goodFacts)
		r.h.ThemesPath = writeThemes(t, goodThemes)
		r.h.UnitsPath = writeUnits(t, goodUnits)
		ask := func(tag string) *http.Response {
			req, _ := http.NewRequest("GET", r.srv.URL+route, nil)
			req.Host = r.host
			if tag != "" {
				req.Header.Set("If-None-Match", tag)
			}
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { resp.Body.Close() })
			return resp
		}
		tag := ask("").Header.Get("ETag")
		if tag == "" {
			t.Fatalf("%s: no ETag", route)
		}
		if got := ask(tag); got.StatusCode != http.StatusNotModified {
			t.Errorf("%s: the same tag answered %d", route, got.StatusCode)
		}
		old := web.BuildID
		web.BuildID = "another-build"
		if got := ask(tag); got.StatusCode != 200 || got.Header.Get("ETag") == tag {
			t.Errorf("%s: a tag of another build answered %d", route, got.StatusCode)
		}
		web.BuildID = old
	}
}

// Review F1: a theme id is a tributary name; one that is not is dropped from the themes and counted.
func TestThemesIdsAreShapeCheckedAndCounted(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.ThemesPath = writeThemes(t, `{"version":1,"at":1,"live":true,"approvalsScope":"","themes":[
 {"id":"alpha","project":"p","title":"a","purpose":"x","counts":{"done":0,"flight":0,"approval":0,"owner":0,"open":0},"workers":[],"units":[]},
 {"id":"javascript:alert(1)//\"><x>","project":"p","title":"a","purpose":"x","counts":{"done":0,"flight":0,"approval":0,"owner":0,"open":0},"workers":[],"units":[]}]}`)
	f := themesOf(t, r)["facts"].(map[string]any)
	if th := f["themes"].([]any); len(th) != 1 || th[0].(map[string]any)["id"] != "alpha" {
		t.Errorf("themes %v", th)
	}
	if f["dropped"] != float64(1) {
		t.Errorf("dropped %v", f["dropped"])
	}
}
