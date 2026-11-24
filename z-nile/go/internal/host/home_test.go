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
