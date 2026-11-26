package web

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"syscall"
)

// maxFacts is the largest facts file the daemon reads.
const maxFacts = 8 << 20

// routes is every path the handler answers, the one table ServeHTTP looks in: approving is the person's own act (f0437), so
// no route records an approval, a ruling or a rework, and a new route must be argued in approvals_test.go (Routes lists it).
var routes = map[string]func(*Handler, http.ResponseWriter, *http.Request){
	"/": func(h *Handler, w http.ResponseWriter, _ *http.Request) {
		h.asset(w, "index.html", "text/html; charset=utf-8")
	},
	"/live.js": func(h *Handler, w http.ResponseWriter, _ *http.Request) {
		h.asset(w, "live.js", "text/javascript; charset=utf-8")
	},
	"/api/state":     func(h *Handler, w http.ResponseWriter, _ *http.Request) { h.state(w) },
	"/api/events":    func(h *Handler, w http.ResponseWriter, r *http.Request) { h.events(w, r) },
	"/api/approvals": func(h *Handler, w http.ResponseWriter, r *http.Request) { h.approvals(w, r) },
	"/api/themes":    func(h *Handler, w http.ResponseWriter, r *http.Request) { h.themes(w, r) },
	"/api/units":     func(h *Handler, w http.ResponseWriter, r *http.Request) { h.units(w, r) },
}

// Routes lists the paths of routes.
var Routes = func() []string {
	var out []string
	for p := range routes {
		out = append(out, p)
	}
	return out
}()

// list is a JSON list in the facts file. The engine's encoder (Lune's) cannot tell an empty list from an empty map, so it
// writes an empty list as `{}`: that is read as an empty list, a non-empty object stays an unexpected shape, and an empty
// or missing list is written to the page as `[]`, never `{}` or null.
type list[T any] []T

func (l *list[T]) UnmarshalJSON(b []byte) error {
	var obj map[string]json.RawMessage
	if json.Unmarshal(b, &obj) == nil && obj != nil { // an object (null decodes to a nil map, not here)
		if len(obj) != 0 {
			return fmt.Errorf("a list was written as a non-empty object")
		}
		*l = list[T]{}
		return nil
	}
	var s []T
	if err := json.Unmarshal(b, &s); err != nil {
		return err
	}
	if s == nil {
		s = []T{}
	}
	*l = s
	return nil
}

func (l list[T]) MarshalJSON() ([]byte, error) {
	if l == nil {
		return []byte("[]"), nil
	}
	return json.Marshal([]T(l))
}

// The facts file is written by the engine (`./zn approve <scope> --queue`); these types are the shape the daemon passes on,
// so a field the file holds beyond them is dropped and a file of another shape is reported, not served.
type factIdea struct {
	Problem  string `json:"problem"`
	Solution string `json:"solution"`
}
type factPart struct {
	Heading string `json:"heading"`
	Text    string `json:"text"`
}
type factGuess struct {
	ID    string `json:"id"`
	Step  string `json:"step"`
	When  string `json:"when"`
	Open  string `json:"open"`
	Chose string `json:"chose"`
	Why   string `json:"why"`
}
type factReview struct {
	Name    string `json:"name"`
	Verdict string `json:"verdict"`
}
type factCost struct {
	Tokens  float64 `json:"tokens,omitempty"`
	Minutes float64 `json:"minutes,omitempty"`
}
type factLinks struct {
	PR     string `json:"pr,omitempty"`
	Branch string `json:"branch,omitempty"`
}
type factFenced struct {
	Heading string `json:"heading"`
	Lines   int    `json:"lines"` // lines after that heading that are outside what the owner approves
}
type factTicket struct {
	ID       string           `json:"id"`
	Title    string           `json:"title"`
	Hash     string           `json:"hash"`
	Why      string           `json:"why"`
	Place    string           `json:"place"`
	Idea     factIdea         `json:"idea"`
	Design   list[factPart]   `json:"design"`
	Extra    list[factPart]   `json:"extra"`    // Acceptance criteria and Test plan, whole (f0437 step 6)
	Comments int              `json:"comments"` // template comments the engine dropped
	Fenced   list[factFenced] `json:"fenced"`   // sections the contract ends at a heading inside a code block (review F6)
	Guesses  list[factGuess]  `json:"guesses"`
	Reviews  list[factReview] `json:"reviews"`
	Cost     *factCost        `json:"cost,omitempty"`
	Links    factLinks        `json:"links"`
}
type factRaft struct {
	ID      string           `json:"id"`
	Title   string           `json:"title"`
	Single  bool             `json:"single"`
	Themes  list[string]     `json:"themes"`
	Tickets list[factTicket] `json:"tickets"`
}
type factTheme struct {
	ID      string         `json:"id"`
	Project string         `json:"project"`
	Title   string         `json:"title"`
	Purpose string         `json:"purpose"`
	Rafts   list[factRaft] `json:"rafts"`
}
type facts struct {
	Version int             `json:"version"`
	At      float64         `json:"at"`
	Run     string          `json:"run"`
	Scope   string          `json:"scope"`
	Themes  list[factTheme] `json:"themes"`
}

// approvalsView is the whole of /api/approvals: the facts, or why there are none. It never holds a path.
type approvalsView struct {
	State string `json:"state"` // ok, absent or unreadable
	Why   string `json:"why,omitempty"`
	Facts *facts `json:"facts"`
}

const absentWhy = "No approval facts have been written yet. Run ./zn approve --queue in a terminal; this page updates by itself."

func unreadable(why string) approvalsView { return approvalsView{State: "unreadable", Why: why} }

// readFacts reads the facts file: a regular file of its own (never a link), at most maxFacts, version 1 or 2 (1 was made by an older engine and its texts are clipped), with a themes list.
func (h *Handler) readFacts() (approvalsView, string) {
	if h.FactsPath == "" {
		return approvalsView{State: "absent", Why: absentWhy}, ""
	}
	if _, err := os.Lstat(h.FactsPath); os.IsNotExist(err) {
		return approvalsView{State: "absent", Why: absentWhy}, ""
	}
	f, err := os.OpenFile(h.FactsPath, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return unreadable("the approval facts file cannot be opened (a link or no permission); run ./zn approve --queue again"), ""
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil || !st.Mode().IsRegular() {
		return unreadable("the approval facts are not a regular file; run ./zn approve --queue again"), ""
	}
	if st.Size() > maxFacts {
		return unreadable(fmt.Sprintf("the approval facts are over %d MiB; run ./zn approve --queue again", maxFacts>>20)), ""
	}
	b, err := io.ReadAll(io.LimitReader(f, maxFacts+1))
	if err != nil || len(b) > maxFacts {
		return unreadable("the approval facts cannot be read; run ./zn approve --queue again"), ""
	}
	var raw struct {
		Version int              `json:"version"`
		Themes  *json.RawMessage `json:"themes"`
	}
	if err := json.Unmarshal(b, &raw); err != nil {
		return unreadable("the approval facts are not valid JSON; run ./zn approve --queue again"), ""
	}
	if raw.Version != 1 && raw.Version != 2 {
		return unreadable(fmt.Sprintf("the approval facts are version %d and this daemon reads versions 1 and 2; update ./zn (and restart this daemon) and run ./zn approve --queue again", raw.Version)), ""
	}
	if raw.Themes == nil {
		return unreadable("the approval facts have no themes list; run ./zn approve --queue again"), ""
	}
	var fs facts
	if err := json.Unmarshal(b, &fs); err != nil {
		return unreadable("the approval facts have an unexpected shape; run ./zn approve --queue again"), ""
	}
	return approvalsView{State: "ok", Facts: &fs}, tagOf(b)
}

// approvals answers GET /api/approvals. It reads and reports; nothing here accepts input.
func (h *Handler) approvals(w http.ResponseWriter, r *http.Request) {
	view, tag := h.readFacts()
	serveFacts(w, r, view, tag)
}
