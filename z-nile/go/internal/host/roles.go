package host

import "errors"

// Facts is what is known about one repository from outside the host (in production, from GitHub through gh).
type Facts struct {
	Parent  *RemoteID // the repository this one is a fork of; nil when it is not a fork
	CanPush bool      // the signed-in user owns the repository or may push to it
}

// Lookup asks for the facts of one repository. It is injected: the package never reaches the network itself.
type Lookup func(RemoteID) (Facts, error)

// Outcome says how far the roles could be worked out.
type Outcome string

// The outcomes of Roles.
const (
	Resolved  Outcome = "resolved"  // Upstream and Fork are set
	NeedFork  Outcome = "need-fork" // only the upstream exists: the owner's fork must be made
	Ambiguous Outcome = "ambiguous" // Candidates and Settle say what to pass
	Refused   Outcome = "refused"   // a remote could not be used; Reason says which
)

// Role is a repository that plays a part, with the remote that holds it (Name is empty when no remote does).
type Role struct {
	Name string
	ID   RemoteID
}

// Overrides name remotes of the host for the cases zn cannot work out (the --fork and --upstream options).
type Overrides struct{ Fork, Upstream string }

// Result is what Roles decided.
type Result struct {
	Outcome    Outcome
	Upstream   Role
	Fork       Role
	Merge      bool   // the upstream and the fork are one repository the user may push to: land mode "merge"
	Candidates []Role // for Ambiguous
	Settle     string // for Ambiguous: the option that settles it
	Reason     string
}

// Roles decides which remote is the upstream and which is the owner's fork, from the repositories and what lookup
// says about them, never from the remotes' names.
func Roles(remotes []Remote, lookup Lookup, o Overrides) (Result, error) {
	return Result{}, errors.New("unimplemented")
}
