package host

import (
	"fmt"
	"strings"
)

// Facts is what is known about one repository from outside the host (in production, from GitHub through gh).
type Facts struct {
	Parent  *RemoteID // the repository this one is a fork of; nil when it is not a fork
	CanPush bool      // the signed-in user owns the repository or may push to it
}

// Lookup asks for the facts of one repository. It is injected: this package never reaches the network itself.
type Lookup func(RemoteID) (Facts, error)

// Outcome says how far the roles could be worked out.
type Outcome string

// The outcomes of Roles.
const (
	Resolved  Outcome = "resolved"  // Upstream and Fork are set
	NeedFork  Outcome = "need-fork" // only the upstream exists: the owner's fork must be made
	Ambiguous Outcome = "ambiguous" // Candidates and Settle say what to pass
	Refused   Outcome = "refused"   // no remote, or a remote that could not be used; Reason says which
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

// finder asks lookup; each path of Roles asks for a repository once, which the tests pin.
type finder struct{ lookup Lookup }

func (f *finder) facts(id RemoteID) (Facts, error) {
	v, err := f.lookup(id)
	if err != nil {
		return Facts{}, fmt.Errorf("host: looking up %s: %w", id.label(), err)
	}
	return v, nil
}

func (id RemoteID) label() string {
	if id.Host == "" {
		return id.Repo
	}
	return id.Host + "/" + id.Owner + "/" + id.Repo
}

func roleOf(r Remote) Role { return Role{Name: r.Name, ID: r.Fetch} }

func names(rs []Role) string {
	var n []string
	for _, r := range rs {
		n = append(n, r.Name)
	}
	return strings.Join(n, ", ")
}

// Roles decides which remote is the upstream and which is the owner's fork, from the repositories the remotes point
// at and what lookup says about them. The remotes' names never decide anything; a name only labels the result.
// Overrides (the --fork and --upstream options) win and must name configured remotes.
func Roles(remotes []Remote, lookup Lookup, o Overrides) (Result, error) {
	f := &finder{lookup: lookup}
	pick := func(opt, name string) (*Remote, error) {
		if name == "" {
			return nil, nil
		}
		var have []string
		for i := range remotes {
			have = append(have, remotes[i].Name)
			if remotes[i].Name == name {
				if remotes[i].Err != nil {
					return nil, fmt.Errorf("host: %s %q cannot be used: %w", opt, name, remotes[i].Err)
				}
				return &remotes[i], nil
			}
		}
		return nil, fmt.Errorf("host: %s %q is not a configured remote of the host (configured: %s)", opt, name, strings.Join(have, ", "))
	}
	fork, err := pick("--fork", o.Fork)
	if err != nil {
		return Result{}, err
	}
	up, err := pick("--upstream", o.Upstream)
	if err != nil {
		return Result{}, err
	}
	var usable []Remote // one per repository, the first remote in config order that holds it
	seen := map[RemoteID]bool{}
	for _, r := range remotes {
		if r.Err != nil {
			if fork == nil && up == nil {
				return Result{Outcome: Refused, Reason: fmt.Sprintf("%v; pass --fork and --upstream to choose the remotes to use", r.Err)}, nil
			}
			continue
		}
		if !seen[r.Fetch] {
			seen[r.Fetch] = true
			usable = append(usable, r)
		}
	}
	if len(usable) == 0 {
		return Result{Outcome: Refused, Reason: "the host has no remote with a usable address"}, nil
	}
	switch {
	case fork != nil && up != nil:
		return bothGiven(f, roleOf(*fork), roleOf(*up))
	case fork != nil:
		return forkGiven(f, roleOf(*fork), usable)
	case up != nil:
		return upstreamGiven(f, roleOf(*up), usable)
	}
	return automatic(f, usable)
}

func bothGiven(f *finder, fork, up Role) (Result, error) {
	if fork.ID != up.ID {
		return Result{Outcome: Resolved, Upstream: up, Fork: fork}, nil
	}
	fa, err := f.facts(fork.ID)
	if err != nil {
		return Result{}, err
	}
	if fa.CanPush {
		return Result{Outcome: Resolved, Upstream: up, Fork: fork, Merge: true}, nil
	}
	return Result{Outcome: Ambiguous, Candidates: []Role{up, fork}, Settle: "--fork and --upstream name the same repository, which you cannot push to: pass --fork with the remote of your own fork",
		Reason: "the fork and the upstream are one repository"}, nil
}

func forkGiven(f *finder, fork Role, usable []Remote) (Result, error) {
	fa, err := f.facts(fork.ID)
	if err != nil {
		return Result{}, err
	}
	if fa.Parent != nil {
		up := Role{ID: *fa.Parent}
		for _, u := range usable {
			if u.Fetch == up.ID {
				up = roleOf(u)
			}
		}
		return Result{Outcome: Resolved, Upstream: up, Fork: fork}, nil
	}
	var others []Role
	for _, u := range usable {
		if u.Fetch != fork.ID {
			others = append(others, roleOf(u))
		}
	}
	switch {
	case len(others) == 1:
		return Result{Outcome: Resolved, Upstream: others[0], Fork: fork}, nil
	case len(others) == 0 && fa.CanPush:
		return Result{Outcome: Resolved, Upstream: fork, Fork: fork, Merge: true}, nil
	}
	return Result{Outcome: Ambiguous, Candidates: others, Settle: "pass --upstream with the remote of the repository your fork is for",
		Reason: "the fork is given, but which remote is its upstream is not known"}, nil
}

func upstreamGiven(f *finder, up Role, usable []Remote) (Result, error) {
	var forks []Role
	for _, u := range usable {
		if u.Fetch == up.ID {
			continue
		}
		fa, err := f.facts(u.Fetch)
		if err != nil {
			return Result{}, err
		}
		if fa.CanPush && fa.Parent != nil && *fa.Parent == up.ID {
			forks = append(forks, roleOf(u))
		}
	}
	switch len(forks) {
	case 1:
		return Result{Outcome: Resolved, Upstream: up, Fork: forks[0]}, nil
	case 0:
		ua, err := f.facts(up.ID)
		if err != nil {
			return Result{}, err
		}
		if ua.CanPush {
			return Result{Outcome: Resolved, Upstream: up, Fork: up, Merge: true}, nil
		}
		return Result{Outcome: NeedFork, Upstream: up, Reason: "no remote is your fork of the upstream: make a fork and add it as a remote"}, nil
	}
	return Result{Outcome: Ambiguous, Candidates: forks, Settle: "pass --fork with one of: " + names(forks),
		Reason: "more than one remote is a fork of the upstream you may push to"}, nil
}

func automatic(f *finder, usable []Remote) (Result, error) {
	facts := map[RemoteID]Facts{}
	for _, u := range usable {
		fa, err := f.facts(u.Fetch)
		if err != nil {
			return Result{}, err
		}
		facts[u.Fetch] = fa
	}
	if len(usable) == 1 {
		u := roleOf(usable[0])
		fa := facts[u.ID]
		switch {
		case fa.CanPush && fa.Parent != nil: // a clone of the user's own fork: its parent is the upstream
			return Result{Outcome: Resolved, Upstream: Role{ID: *fa.Parent}, Fork: u}, nil
		case fa.CanPush:
			return Result{Outcome: Resolved, Upstream: u, Fork: u, Merge: true}, nil
		}
		return Result{Outcome: NeedFork, Upstream: u, Reason: "the only remote is a repository you cannot push to: make your own fork of it and add it as a remote"}, nil
	}
	type pair struct{ up, fork Role }
	var pairs []pair
	isParent := map[RemoteID]bool{}
	for _, c := range usable {
		fa := facts[c.Fetch]
		if fa.Parent == nil {
			continue
		}
		for _, p := range usable {
			if p.Fetch == *fa.Parent {
				isParent[p.Fetch] = true
				if fa.CanPush {
					pairs = append(pairs, pair{roleOf(p), roleOf(c)})
				}
			}
		}
	}
	if len(pairs) == 1 {
		return Result{Outcome: Resolved, Upstream: pairs[0].up, Fork: pairs[0].fork}, nil
	}
	if len(pairs) > 1 {
		var cands []Role
		ups := map[RemoteID]bool{}
		for _, p := range pairs {
			ups[p.up.ID] = true
			cands = append(cands, p.fork)
		}
		settle := "pass --fork with one of: " + names(cands)
		if len(ups) > 1 {
			var ur []Role
			for _, p := range pairs {
				ur = append(ur, p.up)
			}
			settle = "pass --upstream with one of: " + names(ur) + " and --fork with one of: " + names(cands)
			cands = append(ur, cands...)
		}
		return Result{Outcome: Ambiguous, Candidates: cands, Settle: settle, Reason: "more than one remote could be your fork"}, nil
	}
	var parents []Role
	for _, u := range usable {
		if isParent[u.Fetch] {
			parents = append(parents, roleOf(u))
		}
	}
	if len(parents) == 1 {
		return Result{Outcome: NeedFork, Upstream: parents[0], Reason: "no remote is a fork of it that you may push to: make your own fork and add it as a remote"}, nil
	}
	var all []Role
	for _, u := range usable {
		all = append(all, roleOf(u))
	}
	return Result{Outcome: Ambiguous, Candidates: all, Settle: "pass --upstream with the remote of the project and --fork with the remote of your fork",
		Reason: "the remotes are not related as an upstream and a fork"}, nil
}
