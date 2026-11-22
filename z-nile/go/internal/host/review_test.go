package host

import (
	"strings"
	"testing"
)

// F4: a refusal never prints a remote's value, which may hold a credential a sibling reader refuses to echo.
func TestWriteRefusalNeverPrintsARemoteValue(t *testing.T) {
	const secret = "s3cr3tV4lue"
	for _, url := range []string{
		"http://me:" + secret + "@github.com/me/old.git",
		"https://me:" + secret + "@github.com/me/old.git",
		"ext::sh -c 'echo " + secret + "'",
		"ftp://me:" + secret + "@example.com/o/r",
	} {
		f := newFixture(t)
		run(t, f.host, "remote", "add", "old", url)
		r := f.open()
		err := r.checkLocalConfig()
		if err == nil {
			t.Errorf("%q: the write was not refused", url)
			continue
		}
		if strings.Contains(err.Error(), secret) {
			t.Errorf("%q: the refusal prints the secret: %v", url, err)
		}
		if !strings.Contains(err.Error(), "remote.old.url") || !strings.Contains(err.Error(), "not shown") {
			t.Errorf("%q: the refusal must name the key and say its value is not shown: %v", url, err)
		}
		if err := r.FetchDefault("old", "main"); err == nil || strings.Contains(err.Error(), secret) {
			t.Errorf("%q: a write through it: %v", url, err)
		}
	}
}

// F4 round 2: two readers share one tokenizer. The write gate asks only the safety reader (CheckAddress), so a remote
// that is safe but oddly shaped never blocks a write; ParseRemote also holds the identity grammar and refuses
// whatever the safety reader refuses, with the same text.
func TestURLAllowedIsTheSafetyReader(t *testing.T) {
	safeOddlyShaped := []string{"a:b", "C:/x", "host:path", "nas:omarchy.git", "git@nas:omarchy.git", "git@github.com:", "https://github.com/o/r/tree/main", "https://github.com/onlyone", "https://githıub.com/o/r", "https://user:pa/ss@github.com/o/r"}
	for _, u := range safeOddlyShaped {
		if err := CheckAddress(u); err != nil {
			t.Errorf("%q: the safety reader refused a safe address: %v", u, err)
		}
		if err := urlAllowed(u); err != nil {
			t.Errorf("%q: the write gate refused a safe address: %v", u, err)
		}
	}
	for _, u := range []string{"ext::sh -c x", "fd::3", "foo::bar", "http://x/r", "git://x/r", "ftp://x/r", "../rel", "rel/path", "", "-oProxyCommand=x", "ssh://-oProxyCommand=x/r", "https:// x",
		"https://user:tok@github.com/o/r", "https://tok@github.com/o/r", "ssh://git:pw@github.com/o/r", "ghp_x@github.com:o/r", "file://otherhost/x/r"} {
		cerr, perr, uerr := CheckAddress(u), ParseRemote2(u), urlAllowed(u)
		if cerr == nil || uerr == nil || perr == nil {
			t.Errorf("%q: CheckAddress %v, urlAllowed %v, ParseRemote %v: all three must refuse", u, cerr, uerr, perr)
			continue
		}
		if cerr.Error() != perr.Error() || cerr.Error() != uerr.Error() {
			t.Errorf("%q: three refusal texts: %q, %q, %q", u, cerr, uerr, perr)
		}
	}
}

// ParseRemote2 is ParseRemote's error alone.
func ParseRemote2(u string) error { _, err := ParseRemote(u); return err }

// F4: git's own stderr may carry a URL with a credential; the error text is scrubbed.
func TestScrubURLs(t *testing.T) {
	in := "fatal: unable to access 'https://me:s3cr3tV4lue@github.com/o/r.git/': x; also ssh://tok3n@host/o/r and https://plain.example/o/r"
	got := scrubURLs(in)
	if strings.Contains(got, "s3cr3tV4lue") || strings.Contains(got, "tok3n") || !strings.Contains(got, "github.com/o/r.git") || !strings.Contains(got, "https://plain.example/o/r") {
		t.Errorf("scrubbed to %q", got)
	}
}

// A git error that quotes a URL with a credential (in its arguments or in its own message) never repeats it.
func TestGitErrorsAreScrubbed(t *testing.T) {
	f := newFixture(t)
	_, err := f.open().readGit("rev-parse", "https://me:s3cr3tV4lue@example.invalid/o/r")
	if err == nil {
		t.Fatal("rev-parse of a URL succeeded")
	}
	if strings.Contains(err.Error(), "s3cr3tV4lue") {
		t.Errorf("the error repeats the credential: %v", err)
	}
}

// round 2 item 5: the exec error scrub. The scrubbed environment drops GIT_CONFIG_*, so the test injects through its own
// seam (the Repo's environment) a git alias that fails with a credential in its stderr.
func TestExecErrorsAreScrubbedOfStderrToo(t *testing.T) {
	f := newFixture(t)
	r := f.open()
	r.reads = append(append([]string{}, r.reads...), "GIT_CONFIG_COUNT=1", "GIT_CONFIG_KEY_0=alias.zz",
		"GIT_CONFIG_VALUE_0=!echo fatal: unable to access https://u:s3cr3tV4lue@x/o/r >&2; exit 1")
	_, err := r.exec(r.reads, []string{"zz"})
	if err == nil {
		t.Fatal("the alias did not fail")
	}
	if strings.Contains(err.Error(), "s3cr3tV4lue") || !strings.Contains(err.Error(), "unable to access https://x/o/r") {
		t.Errorf("stderr not scrubbed, or scrubbed too far: %v", err)
	}
}
