package host

import (
	"errors"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
)

// RemoteID is a remote repository by what it is, not by how its address is spelled (f0428 step 2). It is the one
// reader of remote addresses: https, ssh://, scp-like (git@host:owner/repo) and absolute local paths (fixtures) all
// come out as the same value for the same repository.
type RemoteID struct {
	Host  string // lower-case host without port or user; empty for a local path
	Owner string // everything before the repository name ("owner", or "group/subgroup")
	Repo  string // repository name without .git; for a local path, the cleaned absolute path without .git
}

// Remote is one configured remote of the host with its fetch and push addresses.
type Remote struct {
	Name  string
	Fetch RemoteID
	Push  RemoteID
	Err   error // the remote's address could not be used (a credential, an unusable form); Fetch and Push are then empty
}

// errCredential never carries the address: a secret in it must not reach a message, a log or a settings file.
var errCredential = errors.New("the address carries a credential in its user information (a password or a token): remove it and let git use a credential helper or an ssh key")

var (
	tokenPrefix  = regexp.MustCompile(`(?i)^(gh[pousr]_|github_pat_|glpat-|xox[a-z]-|npm_|sk-)`)
	sshUserOK    = regexp.MustCompile(`^[A-Za-z0-9._-]{1,32}$`)
	hostForbids  = regexp.MustCompile(`[\s\x00-\x1f\x7f/\\@?#]`)
	portSuffix   = regexp.MustCompile(`:[0-9]*$`)
	pathForbids  = regexp.MustCompile(`[\s\x00-\x1f\x7f?#]`)
	errNoAddress = errors.New("the address is empty")
)

// ParseRemote turns a remote address into its identity: .git, a trailing slash, the port, the ssh user and the case of
// the host do not matter. An address with a credential in it is refused, and no error repeats the address.
func ParseRemote(addr string) (RemoteID, error) {
	switch {
	case addr == "":
		return RemoteID{}, errNoAddress
	case strings.HasPrefix(addr, "-"):
		return RemoteID{}, errors.New("the address starts with a dash, which git would read as an option")
	case transportHelper.MatchString(addr):
		return RemoteID{}, errors.New("the address uses a transport helper (name::), which runs a program")
	case strings.HasPrefix(addr, "/"):
		return localID(addr)
	}
	if scheme, rest, ok := strings.Cut(addr, "://"); ok {
		authority, path, _ := strings.Cut(rest, "/")
		path = "/" + path
		userinfo, hostport, hasUser := cutLast(authority, "@")
		scheme = strings.ToLower(scheme)
		if hasUser && (scheme != "ssh" || credentialLike(userinfo)) {
			return RemoteID{}, errCredential
		}
		switch scheme {
		case "https", "ssh":
			return hostedID(trimPort(hostport), path)
		case "file":
			if hasUser || (hostport != "" && strings.ToLower(hostport) != "localhost") {
				return RemoteID{}, errors.New("a file URL names a host other than this machine")
			}
			if !strings.HasPrefix(path, "/") || path == "/" {
				return RemoteID{}, errors.New("the file URL holds no absolute path")
			}
			return localID(path)
		}
		return RemoteID{}, fmt.Errorf("the address uses the %q scheme, not https, ssh or file", safeScheme(scheme))
	}
	// scp-like: [user@]host:path, with no slash before the colon
	head := addr
	if i := strings.Index(addr, "/"); i >= 0 {
		head = addr[:i]
	}
	userinfo, hostPart, hasUser := cutLast(head, "@")
	host, _, hasColon := strings.Cut(hostPart, ":")
	if !hasColon || host == "" {
		return RemoteID{}, errors.New("the address is not an https, ssh or file URL, an scp-like address or an absolute path")
	}
	if hasUser && credentialLike(userinfo) {
		return RemoteID{}, errCredential
	}
	_, afterColon, _ := strings.Cut(hostPart, ":")
	return hostedID(host, afterColon+addr[len(head):])
}

func safeScheme(s string) string {
	if len(s) > 12 || strings.ContainsAny(s, "@:") {
		return "?"
	}
	return s
}

// cutLast splits at the last sep.
func cutLast(s, sep string) (before, after string, found bool) {
	if i := strings.LastIndex(s, sep); i >= 0 {
		return s[:i], s[i+len(sep):], true
	}
	return "", s, false
}

// credentialLike reports whether ssh user information is a password or a token rather than a plain user name.
func credentialLike(userinfo string) bool {
	return strings.Contains(userinfo, ":") || !sshUserOK.MatchString(userinfo) || tokenPrefix.MatchString(userinfo)
}

func trimPort(hostport string) string {
	if strings.HasPrefix(hostport, "[") { // an IPv6 literal keeps its brackets
		if i := strings.Index(hostport, "]"); i >= 0 {
			return hostport[:i+1]
		}
		return hostport
	}
	return portSuffix.ReplaceAllString(hostport, "")
}

func hostedID(host, path string) (RemoteID, error) {
	host = strings.ToLower(host)
	if host == "" || strings.HasPrefix(host, "-") || hostForbids.MatchString(strings.Trim(host, "[]")) {
		return RemoteID{}, errors.New("the address has an unusable host")
	}
	if pathForbids.MatchString(path) {
		return RemoteID{}, errors.New("the address path holds a character that is not part of a repository path")
	}
	path = strings.Trim(path, "/")
	path = strings.TrimSuffix(path, ".git")
	segs := strings.Split(path, "/")
	for _, s := range segs {
		if s == "" || s == "." || s == ".." {
			return RemoteID{}, errors.New("the address path is not owner/repository")
		}
	}
	if len(segs) < 2 {
		return RemoteID{}, errors.New("the address path is not owner/repository")
	}
	return RemoteID{Host: host, Owner: strings.Join(segs[:len(segs)-1], "/"), Repo: segs[len(segs)-1]}, nil
}

func localID(path string) (RemoteID, error) {
	clean := strings.TrimSuffix(filepath.Clean(path), ".git")
	if clean == "" || clean == "/" {
		return RemoteID{}, errors.New("the local address is the filesystem root")
	}
	return RemoteID{Repo: clean}, nil
}

// Remotes lists the repository's configured remotes, in config order, with their addresses as read from the
// repository's own config (an insteadOf rewrite is not applied). A remote whose address cannot be used is listed with
// its Err, which names the remote and never holds the address.
func (r *Repo) Remotes() ([]Remote, error) {
	out, err := r.git("config", "--local", "--list", "-z")
	if err != nil {
		return nil, err
	}
	type addrs struct{ urls, pushes []string }
	var order []string
	byName := map[string]*addrs{}
	for _, ent := range strings.Split(out, "\x00") {
		key, val, _ := strings.Cut(ent, "\n")
		rest, ok := strings.CutPrefix(key, "remote.")
		if !ok {
			continue
		}
		i := strings.LastIndex(rest, ".")
		if i <= 0 {
			continue
		}
		name, variable := rest[:i], rest[i+1:]
		if variable != "url" && variable != "pushurl" {
			continue
		}
		a := byName[name]
		if a == nil {
			a = &addrs{}
			byName[name] = a
			order = append(order, name)
		}
		if variable == "url" {
			a.urls = append(a.urls, val)
		} else {
			a.pushes = append(a.pushes, val)
		}
	}
	var remotes []Remote
	for _, name := range order {
		a := byName[name]
		rm := Remote{Name: name}
		fail := func(what string, err error) {
			rm.Fetch, rm.Push, rm.Err = RemoteID{}, RemoteID{}, fmt.Errorf("remote %q: %s: %w", name, what, err)
		}
		one := func(list []string) (RemoteID, string, error) {
			var first RemoteID
			for i, u := range list {
				id, err := ParseRemote(u)
				if err != nil {
					return RemoteID{}, "an address", err
				}
				if i == 0 {
					first = id
				} else if id != first {
					return RemoteID{}, "its addresses", errors.New("name different repositories")
				}
			}
			return first, "", nil
		}
		var err error
		var what string
		if len(a.urls) == 0 {
			fail("the address", errors.New("none is configured"))
		} else if rm.Fetch, what, err = one(a.urls); err != nil {
			fail(what, err)
		} else if rm.Push = rm.Fetch; len(a.pushes) > 0 {
			if rm.Push, what, err = one(a.pushes); err != nil {
				fail("a push "+what, err)
			}
		}
		remotes = append(remotes, rm)
	}
	return remotes, nil
}
