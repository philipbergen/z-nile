package host

import "errors"

// The front door's reader of the tracker (f0428 step 4). Stubs: the tests come first.

// TrackerReason names why a host's tracker cannot be used.
type TrackerReason string

// The reasons Locate and Prepare refuse, each its own.
const (
	ReasonTrackerLink  TrackerReason = "tracker-not-a-folder"
	ReasonNotClone     TrackerReason = "tracker-not-a-clone"
	ReasonNoRegistry   TrackerReason = "tracker-no-registry"
	ReasonDirty        TrackerReason = "tracker-has-changes"
	ReasonWorktree     TrackerReason = "tracker-worktree-in-the-way"
	ReasonEngineInPlay TrackerReason = "engine-file-in-the-way"
)

// TrackerRefusal is the refusal of a tracker.
type TrackerRefusal struct {
	Reason TrackerReason
	Detail string
}

func (e *TrackerRefusal) Error() string { return "tracker: " + string(e.Reason) + ": " + e.Detail }

// Tracker is the tracker of a host.
type Tracker struct {
	Host string
	Dir  string
	Work string
}

// Locate finds the tracker of the host cwd belongs to, or nil, nil.
func Locate(cwd string) (*Tracker, error) { return nil, errors.New("not built") }

// Prepare makes Work ready for the engine.
func (t *Tracker) Prepare(payloadDir string) ([]string, error) { return nil, errors.New("not built") }
