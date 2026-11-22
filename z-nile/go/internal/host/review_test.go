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
		"-o" + secret,
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

// F4: one reader of remote addresses.
func TestURLAllowedIsTheSameReaderAsParseRemote(t *testing.T) {
	for _, u := range []string{
		"https://github.com/o/r.git", "ssh://git@github.com/o/r", "git@github.com:o/r.git", "/abs/path/r.git", "file:///abs/r.git",
		"a:b", "C:/x", "host:path", "https://user:tok@github.com/o/r", "http://x/r", "git://x/r", "ext::x", "", "-x", "rel/path",
		"https://github.com/o/r/tree/main", "git@github.com:", "ssh://git@host/o/r",
	} {
		_, perr := ParseRemote(u)
		uerr := urlAllowed(u)
		if (perr == nil) != (uerr == nil) {
			t.Errorf("%q: ParseRemote %v, urlAllowed %v", u, perr, uerr)
		}
		if perr != nil && uerr != nil && perr.Error() != uerr.Error() {
			t.Errorf("%q: two refusal texts: %q and %q", u, perr, uerr)
		}
	}
}

// F4: git's own stderr may carry a URL with a credential; the error text is scrubbed.
func TestScrubURLs(t *testing.T) {
	in := "fatal: unable to access 'https://me:s3cr3tV4lue@github.com/o/r.git/': x; also ssh://tok3n@host/o/r and https://plain.example/o/r"
	got := scrubURLs(in)
	if strings.Contains(got, "s3cr3tV4lue") || strings.Contains(got, "tok3n") || !strings.Contains(got, "github.com/o/r.git") || !strings.Contains(got, "https://plain.example/o/r") {
		t.Errorf("scrubbed to %q", got)
	}
}
