// Package live is the live layer's core: one machine's workers, claims and event log, as pure
// functions of requests and events. It opens no socket and no file.
package live

import "time"

// Proto is the wire protocol version every request carries.
const Proto = 1

// Tags are the caller's own labels, carried unchanged on a claim and on its events.
type Tags struct {
	Raft      string `json:"raft,omitempty"`
	Project   string `json:"project,omitempty"`
	Tributary string `json:"tributary,omitempty"`
	Risk      string `json:"risk,omitempty"`
	Round     int    `json:"round,omitempty"`
	Model     string `json:"model,omitempty"`
}

// Event is one append-only record. Beats are not events. Times are epoch seconds with milliseconds.
type Event struct {
	Seq      int64    `json:"seq"`
	At       float64  `json:"at"`
	Kind     string   `json:"kind"`
	Host     string   `json:"host,omitempty"`
	Worker   string   `json:"worker,omitempty"`
	CLI      string   `json:"cli,omitempty"`
	Unit     string   `json:"unit,omitempty"`
	Activity string   `json:"activity,omitempty"`
	Action   string   `json:"action,omitempty"`
	Step     string   `json:"step,omitempty"`
	Needs    string   `json:"needs,omitempty"`
	Limits   []string `json:"limits,omitempty"`
	Tags
	Outcome string `json:"outcome,omitempty"`
	Tokens  int64  `json:"tokens,omitempty"`
	Seconds int64  `json:"seconds,omitempty"`
	Ref     string `json:"ref,omitempty"`
	Reason  string `json:"reason,omitempty"`
	// Worker fields of a registered event, so a replay restores the worker.
	PID     int      `json:"pid,omitempty"`
	Start   string   `json:"start,omitempty"`
	Session string   `json:"session,omitempty"`
	Mode    string   `json:"mode,omitempty"`
	Can     []string `json:"can,omitempty"`
}

// Worker is one running worker's record.
type Worker struct {
	ID      string   `json:"id"`
	CLI     string   `json:"cli"`
	Can     []string `json:"can,omitempty"`
	Host    string   `json:"host,omitempty"`
	PID     int      `json:"pid"`
	Start   string   `json:"start,omitempty"`
	Session string   `json:"session,omitempty"`
	Mode    string   `json:"mode"`
	Started float64  `json:"started"`
	Heard   float64  `json:"heard"`
	State   string   `json:"state"` // idle, working or lost
	Stop    bool     `json:"stop,omitempty"`
	Seen    int64    `json:"seen"`

	heard time.Duration // monotonic time of the last sign of life; the epoch Heard is for records only
}

// Claim is one activity of one unit held by one worker.
type Claim struct {
	Unit     string   `json:"unit"`
	Activity string   `json:"activity"`
	Action   string   `json:"action,omitempty"`
	Step     string   `json:"step,omitempty"`
	Needs    string   `json:"needs,omitempty"`
	Limits   []string `json:"limits,omitempty"`
	Worker   string   `json:"worker"`
	Since    float64  `json:"since"`
	Tags
}

// Snapshot is the state at one seq, written at exit.
type Snapshot struct {
	Seq     int64     `json:"seq"`
	Workers []*Worker `json:"workers"`
	Claims  []*Claim  `json:"claims"`
}

// Request is the one request shape on the wire; fields an op does not use are ignored.
type Request struct {
	Op       string         `json:"op"`
	Dir      string         `json:"dir"`
	Proto    int            `json:"proto"`
	Worker   string         `json:"worker,omitempty"`
	CLI      string         `json:"cli,omitempty"`
	As       string         `json:"as,omitempty"`
	PID      int            `json:"pid,omitempty"`
	Session  string         `json:"session,omitempty"`
	Mode     string         `json:"mode,omitempty"`
	Can      []string       `json:"can,omitempty"`
	Unit     string         `json:"unit,omitempty"`
	Activity string         `json:"activity,omitempty"`
	Action   string         `json:"action,omitempty"`
	Step     string         `json:"step,omitempty"`
	Needs    string         `json:"needs,omitempty"`
	Limit    map[string]int `json:"limit,omitempty"`
	Tags
	Outcome string  `json:"outcome,omitempty"`
	Tokens  int64   `json:"tokens,omitempty"`
	Seconds int64   `json:"seconds,omitempty"`
	Ref     string  `json:"ref,omitempty"`
	Reason  string  `json:"reason,omitempty"`
	Kind    string  `json:"kind,omitempty"` // emit: the kind; events: the filter
	Since   *int64  `json:"since,omitempty"`
	Follow  bool    `json:"follow,omitempty"`
	Timeout float64 `json:"timeout,omitempty"`
}

// Reply is one JSON object: always ok and seq; a refusal adds refused and why.
type Reply map[string]any

// OK reports whether the reply is a success.
func (r Reply) OK() bool { b, _ := r["ok"].(bool); return b }

// Refused returns the refusal word, or "" for a success.
func (r Reply) Refused() string { s, _ := r["refused"].(string); return s }

// Sink stores an event durably before its reply is sent.
type Sink interface{ Append(Event) error }

// Proc is what ps says about one process.
type Proc struct {
	Start  string // the start time as ps prints it
	Zombie bool   // ended but not yet reaped by its parent
}

// Prober looks at operating-system processes.
type Prober interface {
	// Alive is a signal-0 check; permission denied counts as alive.
	Alive(pid int) bool
	// Procs asks ps about the pids in one call; a pid ps does not know is absent. An error means ps itself failed.
	Procs(pids []int) (map[int]Proc, error)
}

// Config builds a Core.
type Config struct {
	Host      string
	Now       func() time.Time     // wall clock: the epoch times of records
	Mono      func() time.Duration // monotonic clock: every comparison of silence; default time.Since(start)
	TickEvery time.Duration        // the interval Tick is called at; 0 turns off the late-tick (sleep) check
	Sink      Sink
	Probe     Prober
	LostAfter time.Duration
}
