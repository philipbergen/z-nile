package host

import (
	"errors"
	"fmt"
	"strings"
	"testing"
)

func id(host, owner, repo string) RemoteID { return RemoteID{Host: host, Owner: owner, Repo: repo} }

var (
	omarchy    = id("github.com", "basecamp", "omarchy")
	myFork     = id("github.com", "me", "omarchy")
	theirFork  = id("github.com", "other", "omarchy")
	myOwn      = id("github.com", "me", "mine")
	stranger   = id("github.com", "zed", "unrelated")
	maintained = id("github.com", "org", "tool")        // the user may push to it and does not own it
	maintFork  = id("github.com", "me", "tool")         // the user's fork of it
	contrib    = id("github.com", "contrib", "mine")    // somebody's fork of myOwn
	otherForge = id("gitlab.example", "g", "elsewhere") // a host the lookup does not serve
)

func ptr(r RemoteID) *RemoteID { return &r }

// world is the fake of what GitHub says; a repository it does not list is unknown to it (an error). It answers for the
// canonical (lower-case) spelling, as GitHub does.
type world struct {
	facts map[RemoteID]Facts
	errs  map[RemoteID]error
	calls map[RemoteID]int
}

func newWorld() *world {
	return &world{calls: map[RemoteID]int{}, errs: map[RemoteID]error{}, facts: map[RemoteID]Facts{
		omarchy:    {},
		myFork:     {Parent: ptr(omarchy), CanPush: true, Owned: true},
		theirFork:  {Parent: ptr(omarchy)},
		myOwn:      {CanPush: true, Owned: true},
		stranger:   {},
		maintained: {CanPush: true},
		maintFork:  {Parent: ptr(maintained), CanPush: true, Owned: true},
		contrib:    {Parent: ptr(myOwn)},
	}}
}

func (w *world) lookup(r RemoteID) (Facts, error) {
	k := r.Key()
	w.calls[k]++
	if err := w.errs[k]; err != nil {
		return Facts{}, err
	}
	f, ok := w.facts[k]
	if !ok {
		return Facts{}, fmt.Errorf("unknown repository %v", r)
	}
	return f, nil
}

func rem(name string, r RemoteID) Remote { return Remote{Name: name, Fetch: r, Push: r} }

func roles(t *testing.T, remotes []Remote, o Overrides) Result {
	t.Helper()
	res, err := Roles(remotes, newWorld().lookup, o)
	if err != nil {
		t.Fatal(err)
	}
	return res
}

func TestRolesNamesNeverDecide(t *testing.T) {
	names := [][2]string{{"origin", "upstream"}, {"origin", "fork"}, {"upstream", "origin"}, {"fork", "origin"}, {"zeta", "alpha"}, {"alpha", "zeta"}, {"mine", "theirs"}, {"theirs", "mine"}}
	for _, n := range names {
		for _, order := range []bool{true, false} {
			up, fk := rem(n[0], omarchy), rem(n[1], myFork)
			remotes := []Remote{up, fk}
			if !order {
				remotes = []Remote{fk, up}
			}
			res := roles(t, remotes, Overrides{})
			if res.Outcome != Resolved || res.Merge {
				t.Fatalf("%v order %v: %+v", n, order, res)
			}
			if res.Upstream.Name != n[0] || res.Upstream.ID != omarchy || res.Fork.Name != n[1] || res.Fork.ID != myFork {
				t.Errorf("%v order %v: upstream %+v fork %+v", n, order, res.Upstream, res.Fork)
			}
		}
	}
}

func TestRolesOneOwnedRemoteIsBoth(t *testing.T) {
	res := roles(t, []Remote{rem("anything", myOwn)}, Overrides{})
	if res.Outcome != Resolved || !res.Merge || res.Upstream.Name != "anything" || res.Fork.Name != "anything" || res.Upstream.ID != myOwn || res.Fork.ID != myOwn {
		t.Errorf("%+v", res)
	}
}

func TestRolesOneForeignRemoteNeedsAFork(t *testing.T) {
	res := roles(t, []Remote{rem("origin", omarchy)}, Overrides{})
	if res.Outcome != NeedFork || res.Merge || res.Upstream.Name != "origin" || res.Upstream.ID != omarchy || res.Fork != (Role{}) {
		t.Errorf("%+v", res)
	}
	if !strings.Contains(res.Reason, "fork") {
		t.Errorf("reason %q does not say a fork must be made", res.Reason)
	}
}

func TestRolesTheClonedForkNamesItsUpstream(t *testing.T) {
	res := roles(t, []Remote{rem("origin", myFork)}, Overrides{})
	if res.Outcome != Resolved || res.Merge || res.Fork.Name != "origin" || res.Upstream.Name != "" || res.Upstream.ID != omarchy {
		t.Errorf("%+v", res)
	}
	// F11: the result says where the nameless upstream is fetched from and into, and adds no remote
	if res.UpstreamURL != "https://github.com/basecamp/omarchy.git" || UpstreamRef("main") != "refs/zn/upstream/main" {
		t.Errorf("upstream address %q, ref %q", res.UpstreamURL, UpstreamRef("main"))
	}
	named := roles(t, []Remote{rem("a", omarchy), rem("b", myFork)}, Overrides{})
	if named.UpstreamURL != "" {
		t.Errorf("a named upstream carries an address: %q", named.UpstreamURL)
	}
}

func TestRolesTwoRemotesOfOneRepositoryAreOneRemote(t *testing.T) {
	res := roles(t, []Remote{rem("a", omarchy), rem("b", omarchy)}, Overrides{})
	if res.Outcome != NeedFork || res.Upstream.ID != omarchy {
		t.Errorf("%+v", res)
	}
	res = roles(t, []Remote{rem("a", myOwn), rem("b", myOwn)}, Overrides{})
	if res.Outcome != Resolved || !res.Merge {
		t.Errorf("%+v", res)
	}
}

func TestRolesAnotherPersonsForkIsNotMine(t *testing.T) {
	res := roles(t, []Remote{rem("origin", omarchy), rem("them", theirFork)}, Overrides{})
	if res.Outcome != NeedFork || res.Upstream.Name != "origin" || res.Fork != (Role{}) {
		t.Errorf("%+v", res)
	}
	res = roles(t, []Remote{rem("them", theirFork), rem("origin", omarchy), rem("x", myFork)}, Overrides{})
	if res.Outcome != Resolved || res.Upstream.Name != "origin" || res.Fork.Name != "x" {
		t.Errorf("%+v", res)
	}
}

func TestRolesTwoCandidateForksAreAmbiguous(t *testing.T) {
	w := newWorld()
	second := id("github.com", "me", "omarchy2")
	w.facts[second] = Facts{Parent: ptr(omarchy), CanPush: true}
	res, err := Roles([]Remote{rem("origin", omarchy), rem("one", myFork), rem("two", second)}, w.lookup, Overrides{})
	if err != nil {
		t.Fatal(err)
	}
	if res.Outcome != Ambiguous || res.Upstream != (Role{}) || res.Fork != (Role{}) {
		t.Fatalf("%+v", res)
	}
	got := map[string]bool{}
	for _, c := range res.Candidates {
		got[c.Name] = true
	}
	if len(got) != 2 || !got["one"] || !got["two"] || !strings.Contains(res.Settle, "--fork") {
		t.Errorf("candidates %+v settle %q", res.Candidates, res.Settle)
	}
}

func TestRolesUnrelatedRepositoriesAreAmbiguous(t *testing.T) {
	res := roles(t, []Remote{rem("a", omarchy), rem("b", stranger)}, Overrides{})
	if res.Outcome != Ambiguous || len(res.Candidates) != 2 || res.Upstream != (Role{}) {
		t.Fatalf("%+v", res)
	}
	if !strings.Contains(res.Settle, "--upstream") || !strings.Contains(res.Settle, "--fork") {
		t.Errorf("settle %q", res.Settle)
	}
	// one of them mine and the other not a parent of it: still unrelated
	res = roles(t, []Remote{rem("a", omarchy), rem("b", myOwn)}, Overrides{})
	if res.Outcome != Ambiguous {
		t.Errorf("%+v", res)
	}
}

func TestRolesTwoUpstreamsAreAmbiguous(t *testing.T) {
	w := newWorld()
	other := id("github.com", "zed", "tool")
	otherFork := id("github.com", "me", "tool")
	w.facts[other] = Facts{}
	w.facts[otherFork] = Facts{Parent: ptr(other), CanPush: true}
	res, err := Roles([]Remote{rem("a", omarchy), rem("b", myFork), rem("c", other), rem("d", otherFork)}, w.lookup, Overrides{})
	if err != nil {
		t.Fatal(err)
	}
	if res.Outcome != Ambiguous || len(res.Candidates) < 2 || res.Settle == "" {
		t.Errorf("%+v", res)
	}
}

func TestRolesSameRepositoryNamedAsBothIsAmbiguousWhenNotMine(t *testing.T) {
	remotes := []Remote{rem("a", omarchy), rem("b", omarchy)}
	res := roles(t, remotes, Overrides{Fork: "a", Upstream: "b"})
	if res.Outcome != Ambiguous || len(res.Candidates) == 0 || !strings.Contains(res.Settle, "--fork") {
		t.Errorf("%+v", res)
	}
	// a repository the user may push to is its own fork
	res = roles(t, []Remote{rem("a", myOwn), rem("b", myOwn)}, Overrides{Fork: "a", Upstream: "b"})
	if res.Outcome != Resolved || !res.Merge {
		t.Errorf("%+v", res)
	}
}

// F2: an override wins only where lookup cannot settle the layout.
func TestRolesOverridesWinWhereLookupCannotSettle(t *testing.T) {
	remotes := []Remote{rem("a", omarchy), rem("b", stranger)}
	res := roles(t, remotes, Overrides{Upstream: "a", Fork: "b"})
	// b is not pushable, so even here it cannot be the fork
	if res.Outcome != Refused {
		t.Errorf("an unpushable fork was accepted: %+v", res)
	}
	remotes = []Remote{rem("a", stranger), rem("b", myOwn)}
	res = roles(t, remotes, Overrides{Upstream: "a", Fork: "b"})
	if res.Outcome != Resolved || res.Upstream.Name != "a" || res.Fork.Name != "b" {
		t.Errorf("%+v", res)
	}
	// and it settles an ambiguity between two forks
	w := newWorld()
	second := id("github.com", "me", "omarchy2")
	w.facts[second] = Facts{Parent: ptr(omarchy), CanPush: true, Owned: true}
	res, err := Roles([]Remote{rem("o", omarchy), rem("one", myFork), rem("two", second)}, w.lookup, Overrides{Fork: "two"})
	if err != nil || res.Outcome != Resolved || res.Fork.Name != "two" || res.Upstream.Name != "o" {
		t.Errorf("%+v %v", res, err)
	}
}

func TestRolesSwappedOverridesAreRefused(t *testing.T) {
	remotes := []Remote{rem("origin", omarchy), rem("mine", myFork)}
	for _, o := range []Overrides{{Fork: "origin", Upstream: "mine"}, {Fork: "origin"}, {Upstream: "mine"}} {
		res := roles(t, remotes, o)
		if res.Outcome != Refused || res.Fork.Name == "origin" {
			t.Errorf("%+v: %+v", o, res)
		}
		if !strings.Contains(res.Reason, "origin") || !strings.Contains(res.Reason, "mine") {
			t.Errorf("%+v: the reason does not name both remotes: %q", o, res.Reason)
		}
	}
}

func TestRolesAForkOverrideMustBePushable(t *testing.T) {
	remotes := []Remote{rem("up", omarchy), rem("them", theirFork), rem("x", stranger)}
	for _, o := range []Overrides{{Fork: "up"}, {Fork: "them"}, {Fork: "them", Upstream: "up"}, {Fork: "x", Upstream: "up"}} {
		res := roles(t, remotes, o)
		if res.Outcome != Refused || !strings.Contains(res.Reason, "cannot push") || res.Fork.Name != "" {
			t.Errorf("%+v: %+v", o, res)
		}
	}
}

func TestRolesForkOfAThirdRepositoryIsRefused(t *testing.T) {
	remotes := []Remote{rem("a", omarchy), rem("b", myFork), rem("c", stranger)}
	res := roles(t, remotes, Overrides{Fork: "b", Upstream: "c"})
	if res.Outcome != Refused || !strings.Contains(res.Reason, "b") || !strings.Contains(res.Reason, "c") {
		t.Errorf("%+v", res)
	}
}

func TestRolesBothOverridesStillLookUp(t *testing.T) {
	w := newWorld()
	res, err := Roles([]Remote{rem("a", omarchy), rem("b", myFork)}, w.lookup, Overrides{Fork: "b", Upstream: "a"})
	if err != nil || res.Outcome != Resolved {
		t.Fatalf("%+v %v", res, err)
	}
	if w.calls[myFork] == 0 {
		t.Error("the fork was never looked up")
	}
	w = newWorld()
	w.errs[myFork] = errors.New("boom")
	if _, err := Roles([]Remote{rem("a", omarchy), rem("b", myFork)}, w.lookup, Overrides{Fork: "b", Upstream: "a"}); err == nil {
		t.Error("a failed lookup of an override was swallowed")
	}
}

// F3: merge mode is for an owned repository, not for one the user may only push to.
func TestRolesMergeNeedsOwnership(t *testing.T) {
	res := roles(t, []Remote{rem("origin", maintained)}, Overrides{})
	if res.Outcome != NeedFork || res.Merge || !strings.Contains(res.Reason, "ownership") {
		t.Errorf("a maintainer's single remote: %+v", res)
	}
	res = roles(t, []Remote{rem("origin", maintained), rem("mine", maintFork)}, Overrides{})
	if res.Outcome != Resolved || res.Merge || res.Upstream.Name != "origin" || res.Fork.Name != "mine" {
		t.Errorf("maintainer plus fork: %+v", res)
	}
	res = roles(t, []Remote{rem("origin", myOwn)}, Overrides{})
	if res.Outcome != Resolved || !res.Merge {
		t.Errorf("an owned repository: %+v", res)
	}
	res = roles(t, []Remote{rem("a", maintained), rem("b", stranger)}, Overrides{Upstream: "a"})
	if res.Outcome != NeedFork || res.Merge {
		t.Errorf("--upstream on a maintained repository: %+v", res)
	}
	res = roles(t, []Remote{rem("a", maintained)}, Overrides{Upstream: "a", Fork: "a"})
	if res.Merge || res.Outcome == Resolved {
		t.Errorf("both overrides on a maintained repository: %+v", res)
	}
	res = roles(t, []Remote{rem("a", maintained), rem("b", stranger)}, Overrides{Fork: "a"})
	if res.Merge {
		t.Errorf("--fork on a maintained repository: %+v", res)
	}
}

// F10: an owned repository whose contributors' forks are extra remotes is still merge mode.
func TestRolesOwnedRepositoryWithAContributorsFork(t *testing.T) {
	res := roles(t, []Remote{rem("origin", myOwn), rem("c", contrib)}, Overrides{})
	if res.Outcome != Resolved || !res.Merge || res.Upstream.Name != "origin" || res.Fork.Name != "origin" {
		t.Errorf("%+v", res)
	}
}

func TestRolesForkOverrideAloneFindsTheUpstream(t *testing.T) {
	res := roles(t, []Remote{rem("a", omarchy), rem("b", myFork), rem("c", stranger)}, Overrides{Fork: "b"})
	if res.Outcome != Resolved || res.Fork.Name != "b" || res.Upstream.Name != "a" {
		t.Errorf("%+v", res)
	}
	// the one other repository is the upstream when the fork's parent is not known
	res = roles(t, []Remote{rem("a", stranger), rem("b", myOwn)}, Overrides{Fork: "b"})
	if res.Outcome != Resolved || res.Fork.Name != "b" || res.Upstream.Name != "a" {
		t.Errorf("%+v", res)
	}
	res = roles(t, []Remote{rem("a", stranger), rem("b", myOwn), rem("c", omarchy)}, Overrides{Fork: "b"})
	if res.Outcome != Ambiguous || !strings.Contains(res.Settle, "--upstream") {
		t.Errorf("%+v", res)
	}
}

func TestRolesUpstreamOverrideAloneFindsTheFork(t *testing.T) {
	res := roles(t, []Remote{rem("a", omarchy), rem("b", myFork), rem("c", stranger)}, Overrides{Upstream: "a"})
	if res.Outcome != Resolved || res.Upstream.Name != "a" || res.Fork.Name != "b" {
		t.Errorf("%+v", res)
	}
	res = roles(t, []Remote{rem("a", omarchy), rem("c", stranger)}, Overrides{Upstream: "a"})
	if res.Outcome != NeedFork || res.Upstream.Name != "a" {
		t.Errorf("%+v", res)
	}
}

func TestRolesOverrideMustBeAConfiguredRemote(t *testing.T) {
	remotes := []Remote{rem("origin", omarchy), rem("fork", myFork)}
	for _, o := range []Overrides{{Fork: "nope"}, {Upstream: "nope"}, {Fork: "fork", Upstream: "nope"}, {Fork: "-x"}} {
		res, err := Roles(remotes, newWorld().lookup, o)
		if err == nil {
			t.Errorf("%+v accepted: %+v", o, res)
			continue
		}
		if !strings.Contains(err.Error(), "origin") || !strings.Contains(err.Error(), "fork") || !strings.Contains(err.Error(), "not a configured remote") {
			t.Errorf("%+v: the refusal does not name the choices: %v", o, err)
		}
	}
}

func TestRolesAnOverrideNamingABrokenRemoteIsRefused(t *testing.T) {
	broken := Remote{Name: "bad", Err: fmt.Errorf("remote %q: %w", "bad", ErrCredential)}
	remotes := []Remote{rem("origin", omarchy), rem("fork", myFork), broken}
	_, err := Roles(remotes, newWorld().lookup, Overrides{Fork: "bad"})
	if err == nil || !strings.Contains(err.Error(), "bad") || !strings.Contains(err.Error(), "credential") {
		t.Errorf("err %v", err)
	}
	// a broken remote nobody named does not stop an override from settling the roles
	res := roles(t, remotes, Overrides{Fork: "fork", Upstream: "origin"})
	if res.Outcome != Resolved || res.Fork.Name != "fork" {
		t.Errorf("%+v", res)
	}
}

func TestRolesABrokenRemoteWithNoOverrideIsRefusedByName(t *testing.T) {
	broken := Remote{Name: "bad", Err: fmt.Errorf("remote %q: %w", "bad", ErrCredential)}
	res := roles(t, []Remote{rem("origin", omarchy), broken}, Overrides{})
	if res.Outcome != Refused || !strings.Contains(res.Reason, "bad") || !strings.Contains(res.Reason, "credential") {
		t.Errorf("%+v", res)
	}
}

func TestRolesNoRemotes(t *testing.T) {
	res := roles(t, nil, Overrides{})
	if res.Outcome != Refused || res.Reason == "" {
		t.Errorf("%+v", res)
	}
}

func TestRolesLookupFailureIsAnErrorAndAsksOncePerRepository(t *testing.T) {
	w := newWorld()
	delete(w.facts, omarchy)
	if _, err := Roles([]Remote{rem("a", omarchy), rem("b", myFork)}, w.lookup, Overrides{}); err == nil {
		t.Error("a failed lookup was swallowed")
	}
	w = newWorld()
	if _, err := Roles([]Remote{rem("a", omarchy), rem("b", omarchy), rem("c", myFork)}, w.lookup, Overrides{}); err != nil {
		t.Fatal(err)
	}
	for r, n := range w.calls {
		if n != 1 {
			t.Errorf("%v asked %d times", r, n)
		}
	}
}

func TestRolesUseTheFetchAddress(t *testing.T) {
	// the push address may be spelled otherwise, the repository is the fetch address's
	up := Remote{Name: "u", Fetch: omarchy, Push: id("github.com", "elsewhere", "x")}
	res := roles(t, []Remote{up, rem("f", myFork)}, Overrides{})
	if res.Outcome != Resolved || res.Upstream.ID != omarchy {
		t.Errorf("%+v", res)
	}
}

// F5, F6: the fork is pushed through its push address, which must be its fetch repository.
func TestRolesAnUpstreamGuardDoesNotBreakIt(t *testing.T) {
	guarded := Remote{Name: "origin", Fetch: omarchy, PushDisabled: true}
	res := roles(t, []Remote{guarded, rem("mine", myFork)}, Overrides{})
	if res.Outcome != Resolved || res.Upstream.Name != "origin" || res.Fork.Name != "mine" {
		t.Errorf("%+v", res)
	}
	res = roles(t, []Remote{guarded, rem("mine", myFork)}, Overrides{Upstream: "origin"})
	if res.Outcome != Resolved {
		t.Errorf("--upstream on a guarded remote: %+v", res)
	}
}

func TestRolesAForkWithNoPushAddressIsRefusedByName(t *testing.T) {
	disabled := Remote{Name: "mine", Fetch: myFork, PushDisabled: true}
	for _, o := range []Overrides{{}, {Fork: "mine"}} {
		res := roles(t, []Remote{rem("origin", omarchy), disabled}, o)
		if res.Outcome != Refused || !strings.Contains(res.Reason, "mine") || res.Fork.Name != "" {
			t.Errorf("%+v: %+v", o, res)
		}
	}
	res := roles(t, []Remote{{Name: "origin", Fetch: myOwn, PushDisabled: true}}, Overrides{})
	if res.Outcome != Refused || res.Merge {
		t.Errorf("merge on a remote that cannot be pushed to: %+v", res)
	}
}

func TestRolesAForkThatPushesElsewhereIsRefused(t *testing.T) {
	elsewhere := Remote{Name: "mine", Fetch: myFork, Push: id("github.com", "other", "x")}
	for _, o := range []Overrides{{}, {Fork: "mine"}, {Fork: "mine", Upstream: "origin"}} {
		res := roles(t, []Remote{rem("origin", omarchy), elsewhere}, o)
		if res.Outcome != Refused || !strings.Contains(res.Reason, "mine") || !strings.Contains(res.Reason, "another repository") {
			t.Errorf("%+v: %+v", o, res)
		}
	}
	// an ssh spelling of the same repository is fine, and the push identity is carried
	ssh, _ := ParseRemote("git@github.com:Me/Omarchy.git")
	same := Remote{Name: "mine", Fetch: myFork, Push: ssh}
	res := roles(t, []Remote{rem("origin", omarchy), same}, Overrides{})
	if res.Outcome != Resolved || res.Fork.Push != ssh || res.Fork.ID != myFork {
		t.Errorf("%+v", res)
	}
}

// F7: one GitHub repository is one identity whatever the case of its spelling.
func TestRolesCaseOfOwnerAndRepositoryDoesNotMatter(t *testing.T) {
	spelled := id("github.com", "Basecamp", "Omarchy")
	res := roles(t, []Remote{rem("upstream", spelled), rem("origin", myFork)}, Overrides{})
	if res.Outcome != Resolved || res.Upstream.Name != "upstream" || res.Fork.Name != "origin" {
		t.Errorf("automatic: %+v", res)
	}
	res = roles(t, []Remote{rem("upstream", spelled), rem("origin", myFork)}, Overrides{Fork: "origin"})
	if res.Outcome != Resolved || res.Upstream.Name != "upstream" {
		t.Errorf("--fork: a remote holds the upstream but it came back nameless: %+v", res)
	}
	res = roles(t, []Remote{rem("a", omarchy), rem("b", spelled)}, Overrides{Fork: "a", Upstream: "b"})
	if res.Outcome != Ambiguous || !strings.Contains(res.Settle, "--fork") {
		t.Errorf("two spellings of one repository named as both: %+v", res)
	}
	res = roles(t, []Remote{rem("a", omarchy), rem("b", spelled)}, Overrides{})
	if res.Outcome != NeedFork {
		t.Errorf("two spellings of one repository are two remotes: %+v", res)
	}
}

// F9: a remote the lookup does not serve is skipped; not being signed in is never "not a fork".
func TestRolesSkipsWhatTheLookupDoesNotServe(t *testing.T) {
	w := newWorld()
	w.errs[otherForge] = ErrNotServed
	local := id("", "", "/backup/x")
	w.errs[local] = fmt.Errorf("wrapped: %w", ErrNotServed)
	res, err := Roles([]Remote{rem("origin", omarchy), rem("mine", myFork), rem("forge", otherForge), rem("backup", local)}, w.lookup, Overrides{})
	if err != nil || res.Outcome != Resolved || res.Upstream.Name != "origin" || res.Fork.Name != "mine" {
		t.Fatalf("%+v %v", res, err)
	}
	res, err = Roles([]Remote{rem("origin", omarchy), rem("forge", otherForge)}, w.lookup, Overrides{})
	if err != nil || res.Outcome != NeedFork || !strings.Contains(res.Reason, "forge") {
		t.Errorf("a skipped remote is named when the outcome is not resolved: %+v %v", res, err)
	}
}

func TestRolesNotSignedInIsNeitherAForkNorAnError(t *testing.T) {
	w := newWorld()
	w.errs[myFork] = fmt.Errorf("gh: %w", ErrNotSignedIn)
	for _, o := range []Overrides{{}, {Fork: "b", Upstream: "a"}} {
		res, err := Roles([]Remote{rem("a", omarchy), rem("b", myFork)}, w.lookup, o)
		if err != nil || res.Outcome != Unknown || !strings.Contains(res.Reason, "gh auth login") || !strings.Contains(res.Reason, "--fork") {
			t.Errorf("%+v: %+v %v", o, res, err)
		}
	}
	w = newWorld()
	w.errs[myFork] = errors.New("rate limited")
	if res, err := Roles([]Remote{rem("a", omarchy), rem("b", myFork)}, w.lookup, Overrides{}); err == nil {
		t.Errorf("a lookup error became %+v", res)
	}
}

// F13: only a credential refuses the whole result; another unusable remote is skipped.
func TestRolesAnUnrelatedUnusableRemoteIsSkipped(t *testing.T) {
	stale := Remote{Name: "old", Err: errors.New(`remote "old": the address uses the "git" scheme`)}
	res := roles(t, []Remote{rem("origin", omarchy), rem("mine", myFork), stale}, Overrides{})
	if res.Outcome != Resolved {
		t.Errorf("%+v", res)
	}
	res = roles(t, []Remote{rem("origin", omarchy), stale}, Overrides{})
	if res.Outcome != NeedFork || !strings.Contains(res.Reason, "old") {
		t.Errorf("the skipped remote is not named: %+v", res)
	}
	res = roles(t, []Remote{stale}, Overrides{})
	if res.Outcome != Refused || !strings.Contains(res.Reason, "old") {
		t.Errorf("%+v", res)
	}
}

// Mutants the review run left alive: each case is one only that rule can refuse.
func TestRolesOwnedUpstreamGivenAloneIsMerge(t *testing.T) {
	res := roles(t, []Remote{rem("a", myOwn), rem("b", stranger)}, Overrides{Upstream: "a"})
	if res.Outcome != Resolved || !res.Merge || res.Fork.Name != "a" {
		t.Errorf("%+v", res)
	}
}

func TestRolesForkGivenAloneMergesOnlyWhenOwned(t *testing.T) {
	res := roles(t, []Remote{rem("a", myOwn)}, Overrides{Fork: "a"})
	if res.Outcome != Resolved || !res.Merge {
		t.Errorf("owned: %+v", res)
	}
	res = roles(t, []Remote{rem("a", maintained)}, Overrides{Fork: "a"})
	if res.Merge || res.Outcome == Resolved {
		t.Errorf("a maintainer's only remote named as fork: %+v", res)
	}
}

// both are pushable, so only the swap rule can refuse this pair
func TestRolesSwappedPushablePairIsRefused(t *testing.T) {
	remotes := []Remote{rem("up", maintained), rem("mine", maintFork)}
	res := roles(t, remotes, Overrides{Fork: "up", Upstream: "mine"})
	if res.Outcome != Refused || !strings.Contains(res.Reason, "swapped") {
		t.Errorf("%+v", res)
	}
}

// a push guard on a remote whose push identity was left as its fetch identity
func TestRolesAPushDisabledForkIsRefusedWhateverItsPushField(t *testing.T) {
	g := Remote{Name: "mine", Fetch: myFork, Push: myFork, PushDisabled: true}
	res := roles(t, []Remote{rem("origin", omarchy), g}, Overrides{})
	if res.Outcome != Refused || !strings.Contains(res.Reason, "no push address") {
		t.Errorf("%+v", res)
	}
}

// round 2 item 1: --fork alone on a pushable upstream the user does not own, with the user's fork as the other remote.
func TestRolesForkAloneOnAnUpstreamTheUserMayPushToIsRefused(t *testing.T) {
	remotes := []Remote{rem("origin", maintained), rem("mine", maintFork)}
	res := roles(t, remotes, Overrides{Fork: "origin"})
	if res.Outcome != Refused || res.Fork.Name != "" || !strings.Contains(res.Reason, "swapped") || !strings.Contains(res.Reason, "origin") || !strings.Contains(res.Reason, "mine") {
		t.Errorf("%+v", res)
	}
	// the other order of the remotes, and a name that is not "origin"
	res = roles(t, []Remote{rem("zz", maintFork), rem("aa", maintained)}, Overrides{Fork: "aa"})
	if res.Outcome != Refused || !strings.Contains(res.Reason, "swapped") {
		t.Errorf("%+v", res)
	}
	// naming the real fork is fine
	res = roles(t, remotes, Overrides{Fork: "mine"})
	if res.Outcome != Resolved || res.Upstream.Name != "origin" || res.Fork.Name != "mine" {
		t.Errorf("%+v", res)
	}
}

// an owned repository named as the fork with a contributor's fork among the remotes is merge, not a fork of the contributor
func TestRolesOwnedForkNamedAloneIgnoresContributorsForks(t *testing.T) {
	res := roles(t, []Remote{rem("a", myOwn), rem("c", contrib)}, Overrides{Fork: "a"})
	if res.Outcome != Resolved || !res.Merge || res.Upstream.Name != "a" || res.Fork.Name != "a" {
		t.Errorf("%+v", res)
	}
}

// round 2 item 3
func TestRolesUnknownMessageSaysWhatSettlesIt(t *testing.T) {
	w := newWorld()
	w.errs[myFork] = ErrNotSignedIn
	remotes := []Remote{rem("a", omarchy), rem("b", myFork)}
	res, _ := Roles(remotes, w.lookup, Overrides{})
	if !strings.Contains(res.Reason, "gh auth login") || !strings.Contains(res.Reason, "or name the remotes") {
		t.Errorf("without overrides: %q", res.Reason)
	}
	res, _ = Roles(remotes, w.lookup, Overrides{Fork: "b", Upstream: "a"})
	if !strings.Contains(res.Reason, "gh auth login") || strings.Contains(res.Reason, "or name the remotes") {
		t.Errorf("with overrides, which are checked against GitHub too: %q", res.Reason)
	}
}

// round 2 item 4: the upstream address of a cloned fork is built from the lookup's answer, which must be usable
func TestRolesRefusesAParentAnswerThatIsNotAnAddress(t *testing.T) {
	for _, parent := range []RemoteID{
		id("gitlab.example", "basecamp", "omarchy"),  // another host
		id("github.com", "basecamp", "my repo"),      // a space
		id("github.com", "basecamp", "a/b"),          // a path-like repository
		id("github.com", "", "omarchy"),              // no owner
		id("github.com", "basecamp", ""),             // no repository
		id("", "", "/etc/passwd"),                    // a local path
		id("github.com", "base camp", "omarchy"),     // a space in the owner
		id("github.com", "basecamp/../x", "omarchy"), // a dot segment
		id("github.com", "basecamp", "omarchy@evil"), // user information smuggled in
	} {
		for _, o := range []Overrides{{}, {Fork: "origin"}} {
			w := newWorld()
			bad := parent
			w.facts[myFork] = Facts{Parent: &bad, CanPush: true, Owned: true}
			res, err := Roles([]Remote{rem("origin", myFork)}, w.lookup, o)
			if err != nil {
				t.Fatal(err)
			}
			if res.Outcome != Refused || res.UpstreamURL != "" || !strings.Contains(res.Reason, "lookup") || !strings.Contains(res.Reason, "origin") {
				t.Errorf("%+v %+v: %+v", parent, o, res)
			}
			for _, part := range []string{"gitlab.example", "my repo", "a/b", "passwd", "evil", "base camp"} {
				if strings.Contains(res.Reason, part) {
					t.Errorf("%+v: the refusal repeats %q: %s", parent, part, res.Reason)
				}
			}
		}
	}
	// a good one still gives the address, and it passes the readers
	w := newWorld()
	res, _ := Roles([]Remote{rem("origin", myFork)}, w.lookup, Overrides{})
	if res.Outcome != Resolved || res.UpstreamURL != "https://github.com/basecamp/omarchy.git" || CheckAddress(res.UpstreamURL) != nil {
		t.Errorf("%+v", res)
	}
}

// a safe remote with no identity is skipped
func TestRolesSkipsASafeRemoteWithNoIdentity(t *testing.T) {
	nas := Remote{Name: "nas", NoIdentity: errors.New("the address path is not owner/repository")}
	res := roles(t, []Remote{rem("origin", omarchy), rem("mine", myFork), nas}, Overrides{})
	if res.Outcome != Resolved {
		t.Errorf("%+v", res)
	}
	res = roles(t, []Remote{rem("origin", omarchy), nas}, Overrides{})
	if res.Outcome != NeedFork || !strings.Contains(res.Reason, "nas") {
		t.Errorf("%+v", res)
	}
	if _, err := Roles([]Remote{rem("origin", omarchy), nas}, newWorld().lookup, Overrides{Fork: "nas"}); err == nil || !strings.Contains(err.Error(), "nas") {
		t.Errorf("a remote with no identity was accepted as an override: %v", err)
	}
	// a transport helper remote refuses the whole result
	helper := Remote{Name: "evil", Err: fmt.Errorf("remote %q: %w", "evil", ErrTransportHelper)}
	res = roles(t, []Remote{rem("origin", omarchy), rem("mine", myFork), helper}, Overrides{})
	if res.Outcome != Refused || !strings.Contains(res.Reason, "evil") {
		t.Errorf("%+v", res)
	}
}
