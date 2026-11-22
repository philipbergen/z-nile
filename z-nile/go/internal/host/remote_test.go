package host

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestParseRemoteFormsAreOneRepository(t *testing.T) {
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

func TestParseRemoteOnlyHostCaseIsFolded(t *testing.T) {
	a, err1 := ParseRemote("https://github.com/Basecamp/Omarchy")
	b, err2 := ParseRemote("https://github.com/basecamp/omarchy")
	if err1 != nil || err2 != nil {
		t.Fatal(err1, err2)
	}
	if a == b {
		t.Errorf("owner and repository case is kept, got %+v == %+v", a, b)
	}
	if a.Owner != "Basecamp" || a.Repo != "Omarchy" {
		t.Errorf("case lost: %+v", a)
	}
}

func TestParseRemoteDifferentRepositoriesDiffer(t *testing.T) {
	ids := map[RemoteID]string{}
	for _, addr := range []string{
		"https://github.com/basecamp/omarchy", "https://github.com/me/omarchy", "https://github.com/basecamp/other",
		"https://gitlab.com/basecamp/omarchy", "https://github.com/g/sub/omarchy",
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
	base := realTemp(t)
	p := filepath.Join(base, "fork.git")
	want, err := ParseRemote(p)
	if err != nil {
		t.Fatal(err)
	}
	if want.Host != "" || want.Repo != filepath.Join(base, "fork") {
		t.Errorf("local identity %+v", want)
	}
	for _, addr := range []string{p + "/", filepath.Join(base, "x", "..", "fork.git"), "file://" + p, "file://" + p + "/"} {
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

func TestParseRemoteRefusesCredentials(t *testing.T) {
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
	} {
		if id, err := ParseRemote(tc.addr); err == nil {
			t.Errorf("%s: %q accepted as %+v", tc.why, tc.addr, id)
		}
	}
}

func TestRemotesAreReadFromTheConfig(t *testing.T) {
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
