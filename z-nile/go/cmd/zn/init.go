package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"znile/internal/host"
)

const exitUsage = 2

const initUsage = "usage: zn init [--gitignore] [--fork <remote>] [--upstream <remote>] [--project <name>] [<tracker-address>]"

// walkthrough is what `zn init` with no address prints. It changes nothing.
const walkthrough = `zn keeps its tickets, designs and reviews in a repository of its own that you own and name yourself, so the
project you work on (the host) never carries them. Set it up once:

1. Create an EMPTY repository for it on GitHub: no README, no licence, no .gitignore. Use the website's
   new-repository page, or run
       gh repo create <you>/<name> --public
   Anything committed to it is public if the repository is public, so choose private if you want the work record
   kept to yourself.
2. In the base directory of the host project (its main checkout), run
       zn init <the address of that repository>
   zn clones it to .tracker there, writes a README and the minimal skeleton into it when it is empty, and pushes that
   to the address you typed (the one thing it sends anywhere). It keeps .tracker, .worktree and .cache out of the host
   through the clone's own .git/info/exclude, so nothing tracked changes and nothing reaches the host's upstream. Add
   --gitignore to put those lines in the host's tracked .gitignore instead, for a host you own (zn never commits it).

zn never creates the repository or an account, never runs gh repo create, and never asks for or reads a token: git and
gh use the sign-in you already have. Running init again changes nothing.

The project's name in the tracker is taken from the upstream repository's name; if that cannot be a project name, or you
want another, pass --project <name> (lower-case words joined by hyphens).
`

// runInit is `zn init`, answered in Go: no engine is started.
func runInit(args []string, d deps) int {
	var (
		o    host.InitOptions
		addr []string
	)
	usage := func(why string) int {
		fmt.Fprintf(d.stderr, "zn init: %s\n%s\n", why, initUsage)
		return exitUsage
	}
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch {
		case a == "--gitignore":
			o.Gitignore = true
		case a == "--project":
			if i+1 >= len(args) {
				return usage("--project needs a name")
			}
			i++
			o.Project = args[i]
		case strings.HasPrefix(a, "--project="):
			o.Project = strings.TrimPrefix(a, "--project=")
		case a == "--fork" || a == "--upstream":
			if i+1 >= len(args) {
				return usage(a + " needs a remote name")
			}
			i++
			if a == "--fork" {
				o.Overrides.Fork = args[i]
			} else {
				o.Overrides.Upstream = args[i]
			}
		case strings.HasPrefix(a, "--fork="):
			o.Overrides.Fork = strings.TrimPrefix(a, "--fork=")
		case strings.HasPrefix(a, "--upstream="):
			o.Overrides.Upstream = strings.TrimPrefix(a, "--upstream=")
		case strings.HasPrefix(a, "-") && a != "-":
			return usage("unknown option " + a)
		default:
			addr = append(addr, a)
		}
	}
	if len(addr) > 1 {
		return usage("one tracker address, not several")
	}
	if len(addr) == 0 {
		io.WriteString(d.stdout, walkthrough)
		return 0
	}
	cwd, err := d.cwd()
	if err != nil {
		fmt.Fprintf(d.stderr, "zn init: %v\n", err)
		return exitRefused
	}
	o.Root, o.Tracker, o.Lookup = cwd, addr[0], d.lookup
	steps, err := host.Init(o)
	for _, s := range steps {
		fmt.Fprintln(d.stdout, s)
	}
	if err != nil {
		fmt.Fprintf(d.stderr, "zn init: %v\n", err)
		return exitRefused
	}
	if len(steps) == 0 {
		fmt.Fprintln(d.stdout, "zn is already set up here: nothing to do")
	}
	return 0
}

// ghRunner runs gh with arguments and returns its output; an error carries gh's own message.
type ghRunner func(args ...string) ([]byte, error)

// runGH is the production runner: the user's own gh, which holds the sign-in. zn never sees a token.
func runGH(args ...string) ([]byte, error) {
	out, err := exec.Command("gh", args...).Output()
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return nil, fmt.Errorf("gh %s: %s", args[0], strings.TrimSpace(string(ee.Stderr)))
		}
		return nil, fmt.Errorf("gh could not be run: %w", err)
	}
	return out, nil
}

// ghLookup answers host.Lookup from gh: a fork's parent, whether the signed-in user may push, and whether they own
// the repository. Only github.com is served.
func ghLookup(gh ghRunner) host.Lookup {
	viewer := ""
	return func(id host.RemoteID) (host.Facts, error) {
		if id.Host != "github.com" {
			return host.Facts{}, host.ErrNotServed
		}
		notSignedIn := func(err error) error {
			m := strings.ToLower(err.Error())
			if strings.Contains(m, "gh auth login") || strings.Contains(m, "not logged in") || strings.Contains(m, "authentication") || strings.Contains(m, "http 401") {
				return host.ErrNotSignedIn
			}
			return err
		}
		out, err := gh("api", "--hostname", "github.com", "repos/"+id.Owner+"/"+id.Repo)
		if err != nil {
			return host.Facts{}, notSignedIn(err)
		}
		var r struct {
			Parent *struct {
				FullName string `json:"full_name"`
			} `json:"parent"`
			Permissions struct{ Push, Admin bool }   `json:"permissions"`
			Owner       struct{ Login, Type string } `json:"owner"`
		}
		if err := json.Unmarshal(out, &r); err != nil {
			return host.Facts{}, fmt.Errorf("gh answered for %s/%s with something zn cannot read", id.Owner, id.Repo)
		}
		fa := host.Facts{CanPush: r.Permissions.Push}
		if r.Parent != nil {
			if o, n, ok := strings.Cut(r.Parent.FullName, "/"); ok {
				fa.Parent = &host.RemoteID{Host: "github.com", Owner: o, Repo: n}
			}
		}
		if r.Permissions.Push {
			if viewer == "" {
				u, err := gh("api", "--hostname", "github.com", "user")
				if err != nil {
					return host.Facts{}, notSignedIn(err)
				}
				var v struct{ Login string }
				if json.Unmarshal(u, &v) != nil || v.Login == "" {
					return host.Facts{}, errors.New("gh did not say who is signed in")
				}
				viewer = v.Login
			}
			fa.Owned = strings.EqualFold(r.Owner.Login, viewer) || (r.Owner.Type == "Organization" && r.Permissions.Admin)
		}
		return fa, nil
	}
}

func osCwd() (string, error) { return os.Getwd() }
