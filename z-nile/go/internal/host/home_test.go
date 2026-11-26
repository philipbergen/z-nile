package host

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The fixture HOME's git config reaches the code under test (the product's own writes apply the user's global config), so
// it holds an identity and nothing else: a setting that changes how git behaves there would change what the security tests
// see (c0179 code review F1). The tests' own git calls take their template from GIT_TEMPLATE_DIR instead.
func TestFixtureHomeGitConfigHoldsOnlyAnIdentity(t *testing.T) {
	b, err := os.ReadFile(filepath.Join(os.Getenv("HOME"), ".gitconfig"))
	if err != nil {
		t.Fatal(err)
	}
	section := ""
	for _, l := range strings.Split(string(b), "\n") {
		l = strings.TrimSpace(l)
		switch {
		case l == "":
		case strings.HasPrefix(l, "["):
			section = l
			if section != "[user]" {
				t.Errorf("the fixture HOME's .gitconfig has the section %s", section)
			}
		case !strings.HasPrefix(l, "name") && !strings.HasPrefix(l, "email"):
			t.Errorf("the fixture HOME's .gitconfig has the line %q under %s", l, section)
		}
	}
}

// The front-door template's host config still names remotes, whose repositories the template leaves out: they name a folder
// that is plainly missing, so a test that tried to reach them would fail with that name (c0179 design review C4).
func TestFrontTemplateRemotesNameAPlainlyMissingFolder(t *testing.T) {
	t.Parallel()
	f := newFrontFixture(t)
	for _, name := range []string{"origin", "fork"} {
		url := run(t, f.host, "config", "remote."+name+".url")
		if !strings.Contains(url, "missing-in-the-front-door-template") {
			t.Errorf("remote %s is %q, want a folder named missing-in-the-front-door-template", name, url)
		}
		if _, err := os.Stat(url); err == nil {
			t.Errorf("remote %s names a folder that exists: %s", name, url)
		}
	}
}
