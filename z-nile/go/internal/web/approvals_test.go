package web_test

import (
	"encoding/json"
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"syscall"
	"testing"
	"time"

	"znile/internal/live"
	"znile/internal/web"
)

// f0437 step 4: the Approvals view's data. The engine writes the facts file (`./zn approve <scope> --queue`); the daemon
// serves it, GET only, and never records or accepts an approval.

const goodFacts = `{"version":1,"at":1700000000.5,"run":"20261122T010203Z-a1b2","scope":"R0002","themes":[
 {"id":"alpha","title":"Alpha","purpose":"first theme","rafts":[
  {"id":"R0001","title":"Raft one","tickets":[
   {"id":"c0001","title":"Bottom","hash":"0123abcd","why":"no approval (1 guesses)","place":"origin/main",
    "idea":{"problem":"P1","solution":"S1"},
    "design":[{"heading":"Slim design","text":"D1"}],
    "guesses":[{"id":"G1","step":"design","when":"2026-11-20","open":"which","chose":"this","why":"because"}],
    "reviews":[{"name":"design-review-001","verdict":"pass"}],
    "cost":{"tokens":1200,"minutes":14},
    "links":{"pr":"https://example.test/pr/1","branch":"c0001-x"},
    "secret":"never served"}]}]},
 {"id":"beta","title":"Beta","purpose":"","rafts":[]}]}`

func writeFacts(t *testing.T, text string) string {
	t.Helper()
	p := filepath.Join(t.TempDir(), "approvals.json")
	if err := os.WriteFile(p, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func approvalsOf(t *testing.T, r *rig) map[string]any {
	t.Helper()
	resp := r.get("/api/approvals", r.host, "")
	if resp.StatusCode != 200 || !strings.HasPrefix(resp.Header.Get("Content-Type"), "application/json") {
		t.Fatalf("status %d type %q", resp.StatusCode, resp.Header.Get("Content-Type"))
	}
	var out map[string]any
	if err := json.Unmarshal([]byte(readAll(resp)), &out); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestApprovalsAbsentSaysSo(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.FactsPath = filepath.Join(t.TempDir(), "approvals.json")
	got := approvalsOf(t, r)
	if got["state"] != "absent" || got["facts"] != nil {
		t.Fatalf("got %v", got)
	}
	if why, _ := got["why"].(string); !strings.Contains(why, "./zn approve --queue") || strings.Contains(why, r.h.FactsPath) {
		t.Fatalf("the reason must name the command and no path: %q", why)
	}
}

func TestApprovalsServesTheFactsAndOnlyTheKnownFields(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.FactsPath = writeFacts(t, goodFacts)
	got := approvalsOf(t, r)
	if got["state"] != "ok" {
		t.Fatalf("got %v", got)
	}
	facts := got["facts"].(map[string]any)
	themes := facts["themes"].([]any)
	if len(themes) != 2 || themes[0].(map[string]any)["id"] != "alpha" {
		t.Fatalf("themes keep their order: %v", themes)
	}
	tk := themes[0].(map[string]any)["rafts"].([]any)[0].(map[string]any)["tickets"].([]any)[0].(map[string]any)
	for _, k := range []string{"idea", "design", "guesses", "reviews", "cost", "links"} {
		if tk[k] == nil {
			t.Errorf("ticket lacks %s", k)
		}
	}
	if _, has := tk["secret"]; has {
		t.Error("an unknown field was passed through")
	}
	if facts["scope"] != "R0002" || tk["hash"] != "0123abcd" {
		t.Errorf("scope %v hash %v", facts["scope"], tk["hash"])
	}
	if facts["run"] != "20261122T010203Z-a1b2" {
		t.Errorf("run %v", facts["run"])
	}
}

func TestApprovalsUnreadableFileIsNamedNotServed(t *testing.T) {
	for name, text := range map[string]string{"not json": "{", "wrong version": `{"version":2,"themes":[]}`, "no themes": `{"version":1}`} {
		r := newRig(t, "", 0)
		r.h.FactsPath = writeFacts(t, text)
		got := approvalsOf(t, r)
		if got["state"] != "unreadable" || got["facts"] != nil {
			t.Errorf("%s: got %v", name, got)
		}
		if why, _ := got["why"].(string); why == "" || strings.Contains(why, r.h.FactsPath) {
			t.Errorf("%s: reason %q", name, why)
		}
	}
}

func TestApprovalsRefusesALinkAndAHugeFile(t *testing.T) {
	r := newRig(t, "", 0)
	dir := t.TempDir()
	real := filepath.Join(dir, "real.json")
	os.WriteFile(real, []byte(goodFacts), 0o644)
	link := filepath.Join(dir, "approvals.json")
	if err := os.Symlink(real, link); err != nil {
		t.Skip("no symlinks")
	}
	r.h.FactsPath = link
	if got := approvalsOf(t, r); got["state"] != "unreadable" {
		t.Errorf("a symlink was followed: %v", got)
	}
	big := filepath.Join(dir, "big.json")
	os.WriteFile(big, []byte(`{"version":1,"themes":[],"pad":"`+strings.Repeat("x", 9<<20)+`"}`), 0o644)
	r.h.FactsPath = big
	if got := approvalsOf(t, r); got["state"] != "unreadable" {
		t.Errorf("a file over the cap was read: %v", got)
	}
}

func TestApprovalsIsSameOriginGetOnly(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.FactsPath = writeFacts(t, goodFacts)
	if resp := r.get("/api/approvals", "evil.example:80", ""); resp.StatusCode != 403 {
		t.Errorf("wrong host: %d", resp.StatusCode)
	}
	if resp := r.get("/api/approvals", r.host, "http://evil.example"); resp.StatusCode != 403 {
		t.Errorf("wrong origin: %d", resp.StatusCode)
	}
}

// The hard rule: approving is the person's own act. The daemon has no operation that records an approval or a ruling, and
// the set of routes is the reviewed one: adding a route fails this test until its author has argued it here.
func TestRoutesAreTheReviewedSet(t *testing.T) {
	want := []string{"/", "/api/approvals", "/api/events", "/api/state", "/api/themes", "/live.js"}
	got := append([]string(nil), web.Routes...)
	sort.Strings(got)
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("web.Routes = %v, reviewed set %v", got, want)
	}
}

func TestNoRouteOrMethodCanApprove(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.FactsPath = writeFacts(t, goodFacts)
	for _, path := range []string{"/api/approve", "/api/approvals/approve", "/api/approvals/c0001", "/api/ruling", "/api/rulings", "/api/rework", "/api/send-back", "/api/apply"} {
		if resp := r.get(path, r.host, ""); resp.StatusCode != 404 {
			t.Errorf("GET %s answered %d, want 404", path, resp.StatusCode)
		}
	}
	for _, m := range []string{"POST", "PUT", "PATCH", "DELETE"} {
		for _, path := range []string{"/api/approvals", "/api/approve", "/api/ruling", "/"} {
			req := httptest.NewRequest(m, path, strings.NewReader(`{"ticket":"c0001"}`))
			req.Host = r.host
			rec := httptest.NewRecorder()
			r.h.ServeHTTP(rec, req)
			if rec.Code != http.StatusMethodNotAllowed {
				t.Errorf("%s %s answered %d, want 405", m, path, rec.Code)
			}
		}
	}
}

func TestTheCoreHasNoApproveOp(t *testing.T) {
	core := live.New(live.Config{})
	for _, op := range []string{"approve", "approval", "ruling", "rework", "apply", "send-back"} {
		rep := core.Do(live.Request{Op: op, Proto: live.Proto, Unit: "c0001"})
		if rep.OK() {
			t.Errorf("op %q was accepted", op)
		}
	}
}

// No Go source of the daemon names an operation that records an approval: a new one must be argued here first.
func TestNoGoSourceRecordsAnApproval(t *testing.T) {
	root := filepath.Join("..", "..")
	banned := []string{`"approve"`, `"/api/approve`, `"ruling"`, `"rework"`, `approve --apply`, `os/exec`}
	err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(p, ".go") || strings.HasSuffix(p, "_test.go") {
			return err
		}
		if strings.Contains(filepath.ToSlash(p), "/cmd/zn/") || strings.Contains(filepath.ToSlash(p), "/internal/host/") {
			return nil // the zn binary and the host layer are the person's own commands, not the daemon
		}
		b, _ := os.ReadFile(p)
		in := strings.Contains(filepath.ToSlash(p), "/internal/web/")
		for _, w := range banned {
			if strings.Contains(string(b), w) && (in || w == `"approve"`) {
				t.Errorf("%s names %s", p, w)
			}
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
}

// A named pipe in place of the facts file must not hang the request (f0437 review 5).
func TestApprovalsFifoDoesNotHang(t *testing.T) {
	r := newRig(t, "", 0)
	p := filepath.Join(t.TempDir(), "approvals.json")
	if err := syscall.Mkfifo(p, 0o644); err != nil {
		t.Skip("no fifo")
	}
	r.h.FactsPath = p
	done := make(chan map[string]any, 1)
	go func() { done <- approvalsOf(t, r) }()
	select {
	case got := <-done:
		if got["state"] != "unreadable" {
			t.Errorf("got %v", got)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("the request hung on a named pipe")
	}
}

// Lune's JSON encoder writes an empty table as {}: a real facts file holds {} for a ticket with no guesses, and for no themes.
func TestApprovalsReadsTheEnginesEmptyLists(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.FactsPath = writeFacts(t, `{"version":1,"at":1,"run":"","scope":"","themes":{}}`)
	if got := approvalsOf(t, r); got["state"] != "ok" {
		t.Fatalf("no themes: %v", got)
	}
	r.h.FactsPath = writeFacts(t, `{"version":1,"at":1,"run":"20261122T010203Z-a1b2","scope":"","themes":[{"id":"a","title":"a","purpose":"","rafts":[{"id":"c0001","title":"T","single":true,"tickets":[{"id":"c0001","title":"T","hash":"h","why":"w","place":"p","idea":{"problem":"P","solution":"S"},"design":{},"guesses":{},"reviews":{},"links":{}}]}]}]}`)
	if got := approvalsOf(t, r); got["state"] != "ok" {
		t.Fatalf("empty lists in a ticket: %v", got)
	}
}

// f0437 empty lists: the engine's JSON encoder writes an empty list as `{}`; the reader takes that as an empty list.

// engineEmptyGuesses is shaped like what approvalfacts.encode writes (empty lists as {}) for a ticket with no guesses, reviews
// or design (the encoder's form is pinned by tests/tooling/approval-facts.spec.luau, "pins what the encoder writes for an empty list").
const engineEmptyGuesses = `{"at":5,"run":"20261122T010203Z-a1b2","scope":"","themes":[{"id":"alpha","purpose":"first","rafts":[{"id":"R0001","single":false,"tickets":[{"design":{},"guesses":{},"hash":"0123","id":"c0001","idea":{"problem":"P","solution":"S"},"links":{},"place":"origin/main","reviews":{},"title":"T","why":"w"}],"title":"Raft"}],"title":"Alpha"}],"version":1}`

func TestEngineEmptyListFixture(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.FactsPath = writeFacts(t, engineEmptyGuesses)
	got := approvalsOf(t, r)
	if got["state"] != "ok" {
		t.Fatalf("got %v", got)
	}
	tk := got["facts"].(map[string]any)["themes"].([]any)[0].(map[string]any)["rafts"].([]any)[0].(map[string]any)["tickets"].([]any)[0].(map[string]any)
	for _, k := range []string{"design", "guesses", "reviews"} {
		if l, ok := tk[k].([]any); !ok || len(l) != 0 {
			t.Errorf("%s must be an empty list, got %#v", k, tk[k])
		}
	}
}

// factsWith puts one list field empty in the given shape, the others valid.
func factsWith(field, val string) string {
	f := map[string]string{"themes": "[]", "rafts": "[]", "tickets": "[]", "design": "[]", "guesses": "[]", "reviews": "[]"}
	f[field] = val
	return `{"version":1,"themes":` + func() string {
		if field == "themes" {
			return val
		}
		return `[{"id":"a","title":"A","purpose":"","rafts":` + func() string {
			if field == "rafts" {
				return val
			}
			return `[{"id":"R1","title":"R","tickets":` + func() string {
				if field == "tickets" {
					return val
				}
				return `[{"id":"c1","title":"T","design":` + f["design"] + `,"guesses":` + f["guesses"] + `,"reviews":` + f["reviews"] + `}]`
			}() + `}]`
		}() + `}]`
	}() + `}`
}

func TestEveryFactsListTakesAnEmptyObjectAndRefusesAFullOne(t *testing.T) {
	for _, field := range []string{"themes", "rafts", "tickets", "design", "guesses", "reviews"} {
		t.Run(field+" empty object", func(t *testing.T) {
			r := newRig(t, "", 0)
			r.h.FactsPath = writeFacts(t, factsWith(field, "{}"))
			got := approvalsOf(t, r)
			if got["state"] != "ok" {
				t.Fatalf("got %v", got)
			}
		})
		t.Run(field+" full object", func(t *testing.T) {
			r := newRig(t, "", 0)
			r.h.FactsPath = writeFacts(t, factsWith(field, `{"a":1}`))
			got := approvalsOf(t, r)
			if got["state"] != "unreadable" || !strings.Contains(got["why"].(string), "unexpected shape") {
				t.Fatalf("got %v", got)
			}
		})
	}
}

func TestEmptyListsAreWrittenAsArrays(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.FactsPath = writeFacts(t, engineEmptyGuesses)
	resp := r.get("/api/approvals", r.host, "")
	body := readAll(resp)
	for _, k := range []string{`"design":[]`, `"guesses":[]`, `"reviews":[]`} {
		if !strings.Contains(body, k) {
			t.Errorf("%s missing in %s", k, body)
		}
	}
	for _, bad := range []string{`"design":{}`, `"guesses":{}`, `"reviews":{}`, `"themes":null`, `"design":null`, `"guesses":null`, `"reviews":null`} {
		if strings.Contains(body, bad) {
			t.Errorf("an empty list leaked as %s: %s", bad, body)
		}
	}
}

func TestEmptyThemesObjectIsOkWithNoThemes(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.FactsPath = writeFacts(t, `{"version":1,"themes":{}}`)
	resp := r.get("/api/approvals", r.host, "")
	body := readAll(resp)
	if !strings.Contains(body, `"state":"ok"`) || !strings.Contains(body, `"themes":[]`) {
		t.Fatalf("got %s", body)
	}
}

// A list key missing from the file (the only way a list is nil) is served as [], never null.
func TestApprovalsMissingListsAreServedAsEmptyArrays(t *testing.T) {
	r := newRig(t, "", 0)
	r.h.FactsPath = writeFacts(t, `{"version":1,"themes":[{"id":"a","title":"A","purpose":"","rafts":[{"id":"R1","title":"R"}]},{"id":"b","title":"B","purpose":""}]}`)
	body := readAll(r.get("/api/approvals", r.host, ""))
	if !strings.Contains(body, `"state":"ok"`) {
		t.Fatalf("got %s", body)
	}
	for _, want := range []string{`"tickets":[]`, `"rafts":[]`} {
		if !strings.Contains(body, want) {
			t.Errorf("%s missing in %s", want, body)
		}
	}
	r.h.FactsPath = writeFacts(t, `{"version":1,"themes":[{"id":"a","title":"A","purpose":"","rafts":[{"id":"R1","title":"R","tickets":[{"id":"c1","title":"T"}]}]}]}`)
	body = readAll(r.get("/api/approvals", r.host, ""))
	for _, want := range []string{`"design":[]`, `"guesses":[]`, `"reviews":[]`} {
		if !strings.Contains(body, want) {
			t.Errorf("%s missing in %s", want, body)
		}
	}
	if strings.Contains(body, "null") {
		t.Errorf("a missing list leaked as null: %s", body)
	}
}
