package host

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestParseRemoteFormsAreOneRepository(t *testing.T) {
	t.Parallel()
	want := RemoteID{Host: "github.com", Owner: "basecamp", Repo: "omarchy"}
	for _, addr := range []string{
		"https://github.com/basecamp/omarchy",
		"https://github.com/basecamp/omarchy.git",
		"https://github.com/basecamp/omarchy/",
		"https://github.com/basecamp/omarchy.git/",
		"https://GitHub.COM/basecamp/omarchy.git",
		"ssh://git@github.com/basecamp/omarchy",
		"ssh://git@github.com/basecamp/omarchy.git",
		"ssh://git@GITHUB.com:22/basecamp/omarchy.git",
		"git@github.com:basecamp/omarchy.git",
		"git@github.com:basecamp/omarchy",
		"git@GitHub.com:basecamp/omarchy/",
		"github.com:basecamp/omarchy.git",
		"https://github.com:443/basecamp/omarchy.git",
	} {
		got, err := ParseRemote(addr)
		if err != nil {
			t.Errorf("%q: %v", addr, err)
			continue
		}
		if got != want {
			t.Errorf("%q = %+v, want %+v", addr, got, want)
		}
	}
}

func TestParseRemoteCaseIsKeptForDisplayAndFoldedForComparison(t *testing.T) {
	t.Parallel()
	a, err1 := ParseRemote("https://github.com/Basecamp/Omarchy")
	b, err2 := ParseRemote("git@GitHub.com:basecamp/omarchy.git")
	if err1 != nil || err2 != nil {
		t.Fatal(err1, err2)
	}
	if a.Owner != "Basecamp" || a.Repo != "Omarchy" {
		t.Errorf("the spelled case is lost: %+v", a)
	}
	if !a.Same(b) || a.Key() != b.Key() {
		t.Errorf("one repository, two identities: %+v and %+v", a, b)
	}
	c, _ := ParseRemote("https://github.com/basecamp/other")
	if a.Same(c) {
		t.Error("two repositories are one")
	}
}

func TestParseRemoteDifferentRepositoriesDiffer(t *testing.T) {
	t.Parallel()
	ids := map[RemoteID]string{}
	for _, addr := range []string{
		"https://github.com/basecamp/omarchy", "https://github.com/me/omarchy", "https://github.com/basecamp/other",
		"https://gitlab.com/basecamp/omarchy", "https://gitlab.com/g/sub/omarchy",
	} {
		id, err := ParseRemote(addr)
		if err != nil {
			t.Fatal(addr, err)
		}
		if prev, dup := ids[id]; dup {
			t.Errorf("%q and %q are one identity %+v", addr, prev, id)
		}
		ids[id] = addr
	}
	if id, _ := ParseRemote("https://gitlab.com/g/sub/repo.git"); id.Owner != "g/sub" || id.Repo != "repo" {
		t.Errorf("a subgroup stays in the owner: %+v", id)
	}
}

func TestParseRemoteLocalPaths(t *testing.T) {
	t.Parallel()
	base := realTemp(t)
	p := filepath.Join(base, "fork.git")
	want, err := ParseRemote(p)
	if err != nil {
		t.Fatal(err)
	}
	if want.Host != "" || want.Repo != p {
		t.Errorf("local identity %+v", want)
	}
	for _, addr := range []string{p + "/", filepath.Join(base, "x", "..", "fork.git"), "file://" + p, "file://" + p + "/", "file://localhost" + p} {
		got, err := ParseRemote(addr)
		if err != nil || got != want {
			t.Errorf("%q = %+v, %v; want %+v", addr, got, err, want)
		}
	}
	other, _ := ParseRemote(filepath.Join(base, "upstream.git"))
	if other == want {
		t.Error("two local repositories compare equal")
	}
}

// F14: /x/r.git and /x/r are two repositories; /x/.git is /x; a symlinked spelling is the same place.
func TestParseRemoteLocalIdentitiesDoNotCollapseOrSplit(t *testing.T) {
	t.Parallel()
	base := realTemp(t)
	for _, d := range []string{"r.git", "r", "x"} {
		if err := os.MkdirAll(filepath.Join(base, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	a, _ := ParseRemote(filepath.Join(base, "r.git"))
	b, _ := ParseRemote(filepath.Join(base, "r"))
	if a == b {
		t.Errorf("/x/r.git and /x/r are one identity: %+v", a)
	}
	dotgit, _ := ParseRemote(filepath.Join(base, "x", ".git"))
	plain, _ := ParseRemote(filepath.Join(base, "x"))
	if dotgit != plain || dotgit.Repo != filepath.Join(base, "x") {
		t.Errorf("/x/.git = %+v, want /x = %+v", dotgit, plain)
	}
	link := filepath.Join(realTemp(t), "link")
	if err := os.Symlink(base, link); err != nil {
		t.Fatal(err)
	}
	viaLink, err := ParseRemote(filepath.Join(link, "r.git"))
	if err != nil || viaLink != a {
		t.Errorf("a symlinked spelling: %+v, %v; want %+v", viaLink, err, a)
	}
}

func TestParseRemoteRefusesCredentials(t *testing.T) {
	t.Parallel()
	const secret = "s3cr3tV4lue"
	for _, addr := range []string{
		"https://user:" + secret + "@github.com/o/r.git",
		"https://:" + secret + "@github.com/o/r.git",
		"https://" + secret + "@github.com/o/r.git",
		"https://ghp_" + secret + "@github.com/o/r.git",
		"https://x-access-token:" + secret + "@github.com/o/r",
		"ssh://git:" + secret + "@github.com/o/r.git",
		"ssh://ghp_" + secret + "@github.com/o/r.git",
		"user:" + secret + "@github.com:o/r.git",
		"github_pat_" + secret + "@github.com:o/r.git",
		"https://git@github.com/o/r.git",
	} {
		id, err := ParseRemote(addr)
		if err == nil {
			t.Errorf("%q accepted as %+v", addr, id)
			continue
		}
		msg := err.Error()
		if !strings.Contains(msg, "credential") {
			t.Errorf("%q: the refusal does not say credential: %q", addr, msg)
		}
		if strings.Contains(msg, secret) || strings.Contains(msg, addr) || strings.Contains(msg, "user:") {
			t.Errorf("%q: the refusal echoes the address or the secret: %q", addr, msg)
		}
		if id != (RemoteID{}) {
			t.Errorf("%q: an identity came back with the refusal: %+v", addr, id)
		}
	}
}

func TestParseRemoteRefusesWhatIsNotAnAddress(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct{ addr, why string }{
		{"", "empty"},
		{"http://github.com/o/r", "http"},
		{"ext::sh -c touch% x", "helper"},
		{"fd::3", "helper"},
		{"-oProxyCommand=x", "dash"},
		{"--upload-pack=x", "dash"},
		{"git@github.com:", "no path"},
		{"https://github.com/", "no path"},
		{"https://github.com/onlyone", "no owner"},
		{"https://github.com/o/../r", "dotdot"},
		{"relative/path.git", "relative"},
		{"ftp://github.com/o/r", "scheme"},
		{"https:///o/r", "no host"},
		{"https://github.com/o/r@x", "at sign in a path"},
		{"https://github.com/o/r:x", "colon in a path"},
		{"https://github.com/o/%72", "percent"},
		{"https://githıub.com/o/r", "non-ascii host"},
		{"https://github.com/o/r/tree/main", "a web path on github"},
		{"https://github.com/o/r/blob/main/x", "a web path on github"},
		{"https://gitlab.com/g/-/tree/main", "a gitlab web path"},
		{"git@[::1:o/r", "broken ipv6"},
		{"https://exa mple.com/o/r", "space in host"},
		{"https://exa:mple.com/o/r", "colon inside a host"},
		{"https://-bad.example/o/r", "host starting with a dash"},
		{"https://bad_host.example/o/r", "underscore in a host"},
	} {
		if id, err := ParseRemote(tc.addr); err == nil {
			t.Errorf("%s: %q accepted as %+v", tc.why, tc.addr, id)
		}
	}
}

func TestRemotesAreReadFromTheConfig(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	run(t, f.host, "remote", "set-url", "--push", "fork", "git@github.com:me/omarchy.git")
	run(t, f.host, "config", "--local", "url.https://elsewhere.invalid/.insteadOf", f.upstream)
	got, err := f.open().Remotes()
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0].Name != "origin" || got[1].Name != "fork" {
		t.Fatalf("remotes %+v", got)
	}
	up, _ := ParseRemote(f.upstream)
	fk, _ := ParseRemote(f.fork)
	pushed, _ := ParseRemote("https://github.com/me/omarchy")
	if got[0].Fetch != up || got[0].Push != up {
		t.Errorf("origin %+v, want fetch and push %+v (an insteadOf rewrite must not apply)", got[0], up)
	}
	if got[1].Fetch != fk || got[1].Push != pushed {
		t.Errorf("fork %+v, want fetch %+v push %+v", got[1], fk, pushed)
	}
}

func TestRemotesCredentialIsNotStoredOrEchoed(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	const secret = "s3cr3tV4lue"
	run(t, f.host, "remote", "add", "backup", "https://me:"+secret+"@example.com/me/backup.git")
	got, err := f.open().Remotes()
	if err != nil {
		t.Fatal(err)
	}
	var backup *Remote
	for i := range got {
		if got[i].Name == "backup" {
			backup = &got[i]
		}
	}
	if backup == nil || backup.Err == nil {
		t.Fatalf("backup %+v: want a refusal", backup)
	}
	if strings.Contains(backup.Err.Error(), secret) || backup.Fetch != (RemoteID{}) || backup.Push != (RemoteID{}) {
		t.Errorf("secret echoed or identity kept: %+v", backup)
	}
	if !strings.Contains(backup.Err.Error(), "backup") {
		t.Errorf("the refusal does not name the remote: %v", backup.Err)
	}
	for _, r := range got {
		if r.Name != "backup" && r.Err != nil {
			t.Errorf("%s refused: %v", r.Name, r.Err)
		}
	}
}

func TestRemotesPushCredentialIsRefused(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	const secret = "s3cr3tV4lue"
	run(t, f.host, "remote", "set-url", "--push", "fork", "https://me:"+secret+"@example.com/me/omarchy.git")
	got, err := f.open().Remotes()
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range got {
		if r.Name == "fork" && (r.Err == nil || strings.Contains(r.Err.Error(), secret)) {
			t.Errorf("fork: %+v", r)
		}
	}
}

func TestRemotesSeveralAddressesOfOneRepositoryAreFine(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	run(t, f.host, "remote", "set-url", "--add", "fork", f.fork+"/")
	run(t, f.host, "config", "--local", "--add", "remote.fork.url", "file://"+f.fork)
	got, err := f.open().Remotes()
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range got {
		if r.Err != nil {
			t.Errorf("%s: %v", r.Name, r.Err)
		}
	}
}

func TestRemotesSeveralRepositoriesUnderOneNameAreRefused(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	run(t, f.host, "remote", "set-url", "--add", "fork", f.upstream)
	got, err := f.open().Remotes()
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range got {
		if r.Name == "fork" && r.Err == nil {
			t.Errorf("fork holds two repositories and was accepted: %+v", r)
		}
	}
}

// F8: a raw password holding "/" must not land in Host or Owner, nor in any message.
func TestParseRemoteRawPasswordWithSlashIsRefusedAndNeverEchoed(t *testing.T) {
	t.Parallel()
	for _, addr := range []string{
		"https://user:pa/ss@github.com/o/r",
		"user:pa/ss@github.com:o/r",
		"https://user:pa/ss@github.com/o/r.git",
		"ssh://git:pa/ss@github.com/o/r",
	} {
		id, err := ParseRemote(addr)
		if err == nil {
			t.Errorf("%q accepted as %+v", addr, id)
			continue
		}
		if strings.Contains(err.Error(), "pa/ss") || strings.Contains(err.Error(), "ss@") || strings.Contains(err.Error(), "user:pa") {
			t.Errorf("%q: the refusal echoes part of the address: %q", addr, err)
		}
		if id != (RemoteID{}) {
			t.Errorf("%q: a refused address left an identity %+v", addr, id)
		}
	}
}

func TestParseRemoteAcceptsWhatTheGrammarAllows(t *testing.T) {
	t.Parallel()
	for addr, want := range map[string]RemoteID{
		"git@[::1]:o/r":                        {Host: "[::1]", Owner: "o", Repo: "r"},
		"ssh://git@[::1]:22/o/r.git":           {Host: "[::1]", Owner: "o", Repo: "r"},
		"https://gitlab.com/group/sub/r.git":   {Host: "gitlab.com", Owner: "group/sub", Repo: "r"},
		"https://git.example.org:8443/o/r.git": {Host: "git.example.org", Owner: "o", Repo: "r"},
		"https://github.com/o/r.with-dots_1~x": {Host: "github.com", Owner: "o", Repo: "r.with-dots_1~x"},
		"git@github.com:o/r.git":               {Host: "github.com", Owner: "o", Repo: "r"},
	} {
		got, err := ParseRemote(addr)
		if err != nil || got != want {
			t.Errorf("%q = %+v, %v; want %+v", addr, got, err, want)
		}
	}
}

// F5: a push address that is not an address (the guard DISABLE) marks the remote push-disabled, not broken.
func TestRemotesAPushGuardIsNotABrokenRemote(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	for _, guard := range []string{"DISABLE", "no_push"} {
		run(t, f.host, "remote", "set-url", "--push", "origin", guard)
		got, err := f.open().Remotes()
		if err != nil {
			t.Fatal(err)
		}
		up, _ := ParseRemote(f.upstream)
		if got[0].Name != "origin" || got[0].Err != nil || !got[0].PushDisabled || got[0].Fetch != up || got[0].Push != (RemoteID{}) {
			t.Errorf("%s: origin %+v", guard, got[0])
		}
		if got[1].PushDisabled {
			t.Errorf("fork is push-disabled: %+v", got[1])
		}
	}
}

// F5: step 1's write refusal accepts such a remote (a fetch from the host with an upstream guard works).
func TestWritesAcceptAPushGuard(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	run(t, f.host, "remote", "set-url", "--push", "origin", "DISABLE")
	r := f.open()
	if err := r.checkLocalConfig(); err != nil {
		t.Fatalf("a DISABLE pushurl refuses every write: %v", err)
	}
	if err := r.FetchDefault("origin", "main"); err != nil {
		t.Fatal(err)
	}
}

// round 2 item 2: a backup remote that is safe but has no owner/repository is not broken, and blocks nothing.
func TestRemotesASafeRemoteWithNoIdentityIsNotBroken(t *testing.T) {
	t.Parallel()
	f := newFixture(t)
	run(t, f.host, "remote", "add", "nas", "git@nas:omarchy.git")
	run(t, f.host, "remote", "add", "nas2", "nas:omarchy.git")
	r := f.open()
	got, err := r.Remotes()
	if err != nil {
		t.Fatal(err)
	}
	for _, rm := range got {
		if rm.Name == "nas" || rm.Name == "nas2" {
			if rm.Err != nil || rm.NoIdentity == nil || rm.Fetch != (RemoteID{}) {
				t.Errorf("%s: %+v", rm.Name, rm)
			}
		} else if rm.Err != nil || rm.NoIdentity != nil {
			t.Errorf("%s: %+v", rm.Name, rm)
		}
	}
	if err := r.checkLocalConfig(); err != nil {
		t.Fatalf("a backup remote refuses every write: %v", err)
	}
	if err := r.FetchDefault("origin", "main"); err != nil {
		t.Fatal(err)
	}
	if err := CheckHost(f.host); err != nil {
		t.Errorf("CheckHost refuses a host with a backup remote: %v", err)
	}
	// Roles beside a resolvable pair resolves, and names the skipped remotes when it does not
	up, _ := ParseRemote(f.upstream)
	fk, _ := ParseRemote(f.fork)
	w := &world{calls: map[RemoteID]int{}, errs: map[RemoteID]error{}, facts: map[RemoteID]Facts{
		up: {}, fk: {Parent: &up, CanPush: true, Owned: true},
	}}
	res, err := Roles(got, w.lookup, Overrides{})
	if err != nil || res.Outcome != Resolved || res.Upstream.Name != "origin" || res.Fork.Name != "fork" {
		t.Fatalf("%+v %v", res, err)
	}
	only := []Remote{got[0], got[2], got[3]}
	res, err = Roles(only, w.lookup, Overrides{})
	if err != nil || res.Outcome != NeedFork || !strings.Contains(res.Reason, "nas") {
		t.Errorf("%+v %v", res, err)
	}
	if _, err := Roles(got, w.lookup, Overrides{Fork: "nas"}); err == nil {
		t.Error("a remote with no identity was named as the fork")
	}
}

// a credential or a transport helper still refuses everything
func TestRemotesAnUnsafeRemoteStillRefusesEverything(t *testing.T) {
	t.Parallel()
	for _, url := range []string{"https://me:s3cr3tV4lue@example.com/o/r.git", "ext::sh -c true"} {
		f := newFixture(t)
		run(t, f.host, "remote", "add", "bad", url)
		r := f.open()
		if err := r.checkLocalConfig(); err == nil {
			t.Errorf("%q: writes run", url)
		}
		if err := CheckHost(f.host); err == nil {
			t.Errorf("%q: CheckHost accepts", url)
		}
		got, _ := r.Remotes()
		res, err := Roles(got, newWorld().lookup, Overrides{})
		if err != nil || res.Outcome != Refused || !strings.Contains(res.Reason, "bad") || strings.Contains(res.Reason, "s3cr3t") {
			t.Errorf("%q: %+v %v", url, res, err)
		}
	}
}
