package host

import (
	"errors"
	"fmt"
	"strings"
	"testing"
)

func id(host, owner, repo string) RemoteID { return RemoteID{Host: host, Owner: owner, Repo: repo} }

var (
	omarchy   = id("github.com", "basecamp", "omarchy")
	myFork    = id("github.com", "me", "omarchy")
	theirFork = id("github.com", "other", "omarchy")
	myOwn     = id("github.com", "me", "mine")
	stranger  = id("github.com", "zed", "unrelated")
)

func ptr(r RemoteID) *RemoteID { return &r }

// world is the fake of what GitHub says; a repository it does not list is unknown to it (an error).
type world struct {
	facts map[RemoteID]Facts
	calls map[RemoteID]int
}

func newWorld() *world {
	return &world{calls: map[RemoteID]int{}, facts: map[RemoteID]Facts{
		omarchy:   {},
		myFork:    {Parent: ptr(omarchy), CanPush: true},
		theirFork: {Parent: ptr(omarchy)},
		myOwn:     {CanPush: true},
		stranger:  {},
	}}
}

func (w *world) lookup(r RemoteID) (Facts, error) {
	w.calls[r]++
	f, ok := w.facts[r]
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

func TestRolesOverridesWin(t *testing.T) {
	// the lookup says myFork is the fork; the override names the other way round
	remotes := []Remote{rem("a", omarchy), rem("b", myFork)}
	res := roles(t, remotes, Overrides{Fork: "a", Upstream: "b"})
	if res.Outcome != Resolved || res.Fork.Name != "a" || res.Upstream.Name != "b" {
		t.Errorf("%+v", res)
	}
	// an override settles what is ambiguous
	remotes = []Remote{rem("a", omarchy), rem("b", stranger)}
	res = roles(t, remotes, Overrides{Upstream: "a", Fork: "b"})
	if res.Outcome != Resolved || res.Upstream.Name != "a" || res.Fork.Name != "b" {
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
	broken := Remote{Name: "bad", Err: errors.New(`remote "bad" carries a credential`)}
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
	broken := Remote{Name: "bad", Err: errors.New(`remote "bad" carries a credential`)}
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
