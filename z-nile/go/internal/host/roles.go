package host

import (
	"errors"
	"fmt"
	"strings"
)

// Facts is what is known about one repository from outside the host (in production, from GitHub through gh).
type Facts struct {
	Parent  *RemoteID // the repository this one is a fork of; nil when it is not a fork
	CanPush bool      // the signed-in user may push to the repository
	Owned   bool      // the signed-in user, or an organisation they own it through, owns the repository: only that gives land mode "merge"
}

// ErrNotServed is what a Lookup returns for a repository it does not serve (a local path, another forge). Not signed in,
// rate limited and not found are errors of their own: they are never "not a fork" and "may not push".
var ErrNotServed = errors.New("the lookup does not serve this host")

// ErrNotSignedIn is what a Lookup returns when it cannot ask because nobody is signed in.
var ErrNotSignedIn = errors.New("not signed in")

// Lookup asks for the facts of one repository. It is injected: this package never reaches the network itself.
type Lookup func(RemoteID) (Facts, error)

// Outcome says how far the roles could be worked out.
type Outcome string

// The outcomes of Roles.
const (
	Resolved  Outcome = "resolved"  // Upstream and Fork are set
	NeedFork  Outcome = "need-fork" // only the upstream exists: the owner's fork must be made
	Ambiguous Outcome = "ambiguous" // Candidates and Settle say what to pass
	Unknown   Outcome = "unknown"   // the lookup could not be asked (not signed in): Reason says what to do
	Refused   Outcome = "refused"   // no remote, or a remote that could not be used; Reason says which
)

// Role is a repository that plays a part, with the remote that holds it (Name is empty when no remote does).
type Role struct {
	Name string
	ID   RemoteID
	Push RemoteID // where `git push <Name>` goes; for a fork it equals ID
}

// Overrides name remotes of the host for the cases zn cannot work out (the --fork and --upstream options).
type Overrides struct{ Fork, Upstream string }

// Result is what Roles decided.
type Result struct {
	Outcome  Outcome
	Upstream Role
	Fork     Role
	// UpstreamURL is where the upstream is fetched from when no remote holds it (Upstream.Name is empty): the https
	// address of the identity lookup returned. The fetch goes into UpstreamRef(default branch); no remote is added.
	UpstreamURL string
	Merge       bool   // the upstream and the fork are one repository the user may push to: land mode "merge"
	Candidates  []Role // for Ambiguous
	Settle      string // for Ambiguous: the option that settles it
	Reason      string
}

// finder asks lookup; each path of Roles asks for a repository once, which the tests pin.
// finder asks the lookup, once per question, and remembers the remotes it had to skip.
type finder struct {
	lookup  Lookup
	skipped []string
}

// facts asks about a repository. served is false for ErrNotServed (the repository is outside what the lookup knows);
// not being signed in and every other failure are errors, never "not a fork" and "may not push".
func (f *finder) facts(id RemoteID) (fa Facts, served bool, err error) {
	fa, err = f.lookup(id)
	switch {
	case errors.Is(err, ErrNotServed):
		return Facts{}, false, nil
	case err != nil:
		return Facts{}, false, fmt.Errorf("host: looking up %s: %w", id.label(), err)
	}
	return fa, true, nil
}

func (id RemoteID) label() string {
	if id.Host == "" {
		return id.Repo
	}
	return id.Host + "/" + id.Owner + "/" + id.Repo
}

func roleOf(r Remote) Role { return Role{Name: r.Name, ID: r.Fetch, Push: r.Push} }

func names(rs []Role) string {
	var n []string
	for _, r := range rs {
		n = append(n, r.Name)
	}
	return strings.Join(n, ", ")
}

// forkProblem says why a remote cannot be the fork (the repository branches are pushed to), or "". git pushes to a
// remote's push address, so that must exist and be the repository the remote fetches from, the one that was looked up.
func forkProblem(r Remote) string {
	switch {
	case r.PushDisabled:
		return fmt.Sprintf("remote %q has no push address (its pushurl is not an address), so no branch can be pushed through it", r.Name)
	case !r.Push.Same(r.Fetch):
		return fmt.Sprintf("remote %q pushes to another repository than it fetches from: a branch pushed through it would go to a repository nobody looked up", r.Name)
	}
	return ""
}

func refused(format string, a ...any) (Result, error) {
	return Result{Outcome: Refused, Reason: fmt.Sprintf(format, a...)}, nil
}

// nameless gives the upstream an address when no remote holds it: the https address of the identity lookup returned.
func nameless(up Role) Result {
	r := Result{Upstream: up}
	if up.Name == "" {
		r.UpstreamURL = up.ID.HTTPSURL()
	}
	return r
}

// UpstreamRef is the ref zn fetches a nameless upstream's default branch into: a name of zn's own, so no remote is
// added to the host and no ref of the owner's is touched.
func UpstreamRef(branch string) string { return "refs/zn/upstream/" + branch }

// Roles decides which remote is the upstream and which is the owner's fork, from the repositories the remotes point
// at and what lookup says about them. The remotes' names never decide anything; a name only labels the result.
// Overrides (the --fork and --upstream options) must name configured remotes, and are checked against the lookup too:
// they win only where the lookup cannot settle the layout, never against what it says.
func Roles(remotes []Remote, lookup Lookup, o Overrides) (Result, error) {
	f := &finder{lookup: lookup}
	res, err := f.roles(remotes, o)
	if errors.Is(err, ErrNotSignedIn) {
		return Result{Outcome: Unknown, Reason: "GitHub could not be asked which remote is the fork, because nobody is signed in: run `gh auth login`, or name the remotes with --fork and --upstream"}, nil
	}
	if err == nil && res.Outcome != Resolved && len(f.skipped) > 0 {
		res.Reason += fmt.Sprintf(" (remotes not used, because their address or host could not be used: %s)", strings.Join(f.skipped, ", "))
	}
	return res, err
}

func (f *finder) roles(remotes []Remote, o Overrides) (Result, error) {
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
			// only a credential refuses the whole result: the owner must clean it. Any other unusable remote is skipped.
			if errors.Is(r.Err, ErrCredential) && fork == nil && up == nil {
				return refused("%v; clean that remote, or name the remotes to use with --fork and --upstream", r.Err)
			}
			f.skipped = append(f.skipped, r.Name)
			continue
		}
		if k := r.Fetch.Key(); !seen[k] {
			seen[k] = true
			usable = append(usable, r)
		}
	}
	if len(usable) == 0 {
		return refused("the host has no remote with a usable address")
	}
	switch {
	case fork != nil && up != nil:
		return f.bothGiven(*fork, *up)
	case fork != nil:
		return f.forkGiven(*fork, usable)
	case up != nil:
		return f.upstreamGiven(*up, usable)
	}
	return f.automatic(usable)
}

func (f *finder) bothGiven(fork, up Remote) (Result, error) {
	fa, fs, err := f.facts(fork.Fetch)
	if err != nil {
		return Result{}, err
	}
	if fork.Fetch.Same(up.Fetch) {
		if fs && fa.Owned {
			if p := forkProblem(fork); p != "" {
				return refused("%s", p)
			}
			return Result{Outcome: Resolved, Upstream: roleOf(up), Fork: roleOf(fork), Merge: true}, nil
		}
		return Result{Outcome: Ambiguous, Candidates: []Role{roleOf(up), roleOf(fork)}, Settle: "--fork and --upstream name the same repository, which you do not own: pass --fork with the remote of your own fork",
			Reason: "the fork and the upstream are one repository"}, nil
	}
	ua, us, err := f.facts(up.Fetch)
	if err != nil {
		return Result{}, err
	}
	switch {
	case fs && !fa.CanPush:
		hint := ""
		if us && ua.Parent != nil && ua.Parent.Same(fork.Fetch) {
			hint = fmt.Sprintf("; remote %q is a fork of it, so --fork and --upstream look swapped", up.Name)
		}
		return refused("you cannot push to remote %q (%s), so it cannot be your fork%s", fork.Name, fork.Fetch.label(), hint)
	case us && ua.Parent != nil && ua.Parent.Same(fork.Fetch):
		return refused("remote %q is a fork of remote %q: --fork and --upstream look swapped", up.Name, fork.Name)
	case fs && fa.Parent != nil && !fa.Parent.Same(up.Fetch):
		return refused("remote %q is a fork of %s, not of the upstream you named (remote %q)", fork.Name, fa.Parent.label(), up.Name)
	}
	if p := forkProblem(fork); p != "" {
		return refused("%s", p)
	}
	return Result{Outcome: Resolved, Upstream: roleOf(up), Fork: roleOf(fork)}, nil
}

func (f *finder) forkGiven(fork Remote, usable []Remote) (Result, error) {
	fa, fs, err := f.facts(fork.Fetch)
	if err != nil {
		return Result{}, err
	}
	if fs && !fa.CanPush {
		hint := ""
		for _, u := range usable {
			if u.Fetch.Same(fork.Fetch) {
				continue
			}
			if ua, us, err := f.facts(u.Fetch); err == nil && us && ua.CanPush && ua.Parent != nil && ua.Parent.Same(fork.Fetch) {
				hint = fmt.Sprintf("; remote %q is a fork of it that you may push to: did you mean --fork %s?", u.Name, u.Name)
			}
		}
		return refused("you cannot push to remote %q (%s), so it cannot be your fork%s", fork.Name, fork.Fetch.label(), hint)
	}
	if p := forkProblem(fork); p != "" {
		return refused("%s", p)
	}
	if fs && fa.Parent != nil {
		up := Role{ID: *fa.Parent}
		for _, u := range usable {
			if u.Fetch.Same(up.ID) {
				up = roleOf(u)
			}
		}
		res := nameless(up)
		res.Outcome, res.Fork = Resolved, roleOf(fork)
		return res, nil
	}
	var others []Role
	for _, u := range usable {
		if !u.Fetch.Same(fork.Fetch) {
			others = append(others, roleOf(u))
		}
	}
	switch {
	case len(others) == 1:
		return Result{Outcome: Resolved, Upstream: others[0], Fork: roleOf(fork)}, nil
	case len(others) == 0 && fs && fa.Owned:
		return Result{Outcome: Resolved, Upstream: roleOf(fork), Fork: roleOf(fork), Merge: true}, nil
	}
	return Result{Outcome: Ambiguous, Candidates: others, Settle: "pass --upstream with the remote of the repository your fork is for",
		Reason: "the fork is given, but which remote is its upstream is not known"}, nil
}

func (f *finder) upstreamGiven(up Remote, usable []Remote) (Result, error) {
	ua, us, err := f.facts(up.Fetch)
	if err != nil {
		return Result{}, err
	}
	if us && ua.Parent != nil {
		for _, u := range usable {
			if u.Fetch.Same(*ua.Parent) {
				return refused("remote %q is itself a fork of remote %q: did you mean --upstream %s?", up.Name, u.Name, u.Name)
			}
		}
	}
	var forks []Role
	var bad []string
	for _, u := range usable {
		if u.Fetch.Same(up.Fetch) {
			continue
		}
		fa, fs, err := f.facts(u.Fetch)
		if err != nil {
			return Result{}, err
		}
		if fs && fa.CanPush && fa.Parent != nil && fa.Parent.Same(up.Fetch) {
			if p := forkProblem(u); p != "" {
				bad = append(bad, p)
				continue
			}
			forks = append(forks, roleOf(u))
		}
	}
	switch len(forks) {
	case 1:
		return Result{Outcome: Resolved, Upstream: roleOf(up), Fork: forks[0]}, nil
	case 0:
		if len(bad) > 0 {
			return refused("%s", bad[0])
		}
		return f.alone(roleOf(up), up, us, ua)
	}
	return Result{Outcome: Ambiguous, Candidates: forks, Settle: "pass --fork with one of: " + names(forks),
		Reason: "more than one remote is a fork of the upstream you may push to"}, nil
}

// alone is the answer for an upstream no fork of yours is a remote of: merge mode when you own it, a fork to make when
// you do not (push access is not ownership).
func (f *finder) alone(role Role, rm Remote, served bool, fa Facts) (Result, error) {
	if served && fa.Owned {
		if p := forkProblem(rm); p != "" {
			return refused("%s", p)
		}
		return Result{Outcome: Resolved, Upstream: role, Fork: role, Merge: true}, nil
	}
	why := "the only repository is one you cannot push to: make your own fork of it and add it as a remote"
	if served && fa.CanPush {
		why = "you may push to the repository but you do not own it, and push access is not ownership: zn works through your own fork of it, so make one and add it as a remote"
	}
	return Result{Outcome: NeedFork, Upstream: role, Reason: why}, nil
}

func (f *finder) automatic(usable []Remote) (Result, error) {
	var cands []Remote
	facts := map[RemoteID]Facts{}
	for _, u := range usable {
		fa, served, err := f.facts(u.Fetch)
		if err != nil {
			return Result{}, err
		}
		if !served {
			f.skipped = append(f.skipped, u.Name)
			continue
		}
		facts[u.Fetch.Key()] = fa
		cands = append(cands, u)
	}
	if len(cands) == 0 {
		return refused("no remote of the host is a repository the lookup can answer for")
	}
	if len(cands) == 1 {
		u := cands[0]
		fa := facts[u.Fetch.Key()]
		if fa.CanPush && fa.Parent != nil { // a clone of the user's own fork: its parent is the upstream
			if p := forkProblem(u); p != "" {
				return refused("%s", p)
			}
			res := nameless(Role{ID: *fa.Parent})
			res.Outcome, res.Fork = Resolved, roleOf(u)
			return res, nil
		}
		return f.alone(roleOf(u), u, true, fa)
	}
	type pair struct{ up, fork Role }
	var pairs []pair
	var bad []string
	isParent := map[RemoteID]bool{}
	for _, c := range cands {
		fa := facts[c.Fetch.Key()]
		if fa.Parent == nil {
			continue
		}
		for _, p := range cands {
			if !p.Fetch.Same(*fa.Parent) {
				continue
			}
			isParent[p.Fetch.Key()] = true
			if !fa.CanPush {
				continue
			}
			if problem := forkProblem(c); problem != "" {
				bad = append(bad, problem)
				continue
			}
			pairs = append(pairs, pair{roleOf(p), roleOf(c)})
		}
	}
	if len(pairs) == 1 {
		return Result{Outcome: Resolved, Upstream: pairs[0].up, Fork: pairs[0].fork}, nil
	}
	if len(pairs) > 1 {
		var cs []Role
		ups := map[RemoteID]bool{}
		for _, p := range pairs {
			ups[p.up.ID.Key()] = true
			cs = append(cs, p.fork)
		}
		settle := "pass --fork with one of: " + names(cs)
		if len(ups) > 1 {
			var ur []Role
			for _, p := range pairs {
				ur = append(ur, p.up)
			}
			settle = "pass --upstream with one of: " + names(ur) + " and --fork with one of: " + names(cs)
			cs = append(ur, cs...)
		}
		return Result{Outcome: Ambiguous, Candidates: cs, Settle: settle, Reason: "more than one remote could be your fork"}, nil
	}
	if len(bad) > 0 {
		return refused("%s", bad[0])
	}
	var parents []Remote
	for _, u := range cands {
		if isParent[u.Fetch.Key()] {
			parents = append(parents, u)
		}
	}
	if len(parents) == 1 {
		return f.alone(roleOf(parents[0]), parents[0], true, facts[parents[0].Fetch.Key()])
	}
	var all []Role
	for _, u := range cands {
		all = append(all, roleOf(u))
	}
	return Result{Outcome: Ambiguous, Candidates: all, Settle: "pass --upstream with the remote of the project and --fork with the remote of your fork",
		Reason: "the remotes are not related as an upstream and a fork"}, nil
}
