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
	// PushDisabled: the push address is not an address (the usual guard on an upstream: DISABLE, no_push); Push is zero.
	PushDisabled bool
	// NoIdentity: the address is safe to run git with but is not owner/repository on a host (a backup remote
	// git@nas:omarchy.git): Roles skips the remote and names it when the outcome is not resolved. Fetch and Push are zero.
	NoIdentity error
	Err        error // the remote's address could not be used (a credential, an unusable form); Fetch and Push are then empty
}

// ErrTransportHelper marks an address that names a transport helper (name::), which runs a program.
var ErrTransportHelper = errors.New("the address uses a transport helper (name::), which runs a program")

// CheckAddress is the safety reader: it refuses an address git must not be run with.
func CheckAddress(addr string) error { return nil }

// ErrCredential marks an address that carries user information. It never carries the address: a secret in it must not
// reach a message, a log or a settings file.
var ErrCredential = errors.New("the address carries user information in front of the host (a user name, a password or a token, all of which count as a credential): remove it and let git use a credential helper or an ssh key")

var (
	tokenPrefix = regexp.MustCompile(`(?i)^(gh[pousr]_|github_pat_|glpat-|xox[a-z]-|npm_|sk-)`)
	sshUserOK   = regexp.MustCompile(`^[A-Za-z0-9._-]{1,32}$`)
	hostName    = regexp.MustCompile(`^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$`)
	hostIPv6    = regexp.MustCompile(`^\[[0-9a-f:.]+\]$`)
	segmentOK   = regexp.MustCompile(`^[A-Za-z0-9._~-]+$`)
	portSuffix  = regexp.MustCompile(`:[0-9]*$`)
)

// ParseRemote turns a remote address into its identity: .git, a trailing slash, the port (a server is its host), the ssh
// user and the case of the host do not matter. The host and every path segment are held to a grammar, so nothing that
// is not a host name (a password with a slash in it) can land in an identity. An address with a credential in it is
// refused. No error repeats the address or any part of it.
func ParseRemote(addr string) (RemoteID, error) {
	switch {
	case addr == "":
		return RemoteID{}, errors.New("the address is empty")
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
			return RemoteID{}, ErrCredential
		}
		switch scheme {
		case "https", "ssh":
			return hostedID(trimPort(hostport), path)
		case "file":
			if hasUser || (hostport != "" && strings.ToLower(hostport) != "localhost") {
				return RemoteID{}, errors.New("a file URL names a host other than this machine")
			}
			if path == "/" {
				return RemoteID{}, errors.New("the file URL holds no absolute path")
			}
			return localID(path)
		}
		return RemoteID{}, errors.New("the address uses a scheme other than https, ssh or file")
	}
	// scp-like: [user@]host:path, with no slash before the colon
	head := addr
	if i := strings.Index(addr, "/"); i >= 0 {
		head = addr[:i]
	}
	userinfo, hostPart, hasUser := cutLast(head, "@")
	var host, afterHost string
	if strings.HasPrefix(hostPart, "[") { // an IPv6 literal: [::1]:path
		end := strings.Index(hostPart, "]")
		if end < 0 || len(hostPart) <= end+1 || hostPart[end+1] != ':' {
			return RemoteID{}, errors.New("the address is not an https, ssh or file URL, an scp-like address or an absolute path")
		}
		host, afterHost = hostPart[:end+1], hostPart[end+2:]
	} else {
		var hasColon bool
		host, afterHost, hasColon = strings.Cut(hostPart, ":")
		if !hasColon || host == "" {
			return RemoteID{}, errors.New("the address is not an https, ssh or file URL, an scp-like address or an absolute path")
		}
	}
	if hasUser && credentialLike(userinfo) {
		return RemoteID{}, ErrCredential
	}
	return hostedID(host, afterHost+addr[len(head):])
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
	if !hostName.MatchString(host) && !hostIPv6.MatchString(host) {
		return RemoteID{}, errors.New("the address has an unusable host")
	}
	path = strings.TrimSuffix(strings.Trim(path, "/"), ".git")
	segs := strings.Split(path, "/")
	for _, s := range segs {
		if !segmentOK.MatchString(s) || s == "." || s == ".." || s == "-" {
			return RemoteID{}, errors.New("the address path is not owner/repository")
		}
	}
	// a web page pasted from a browser (owner/repo/tree/main) is not a repository address on github.com
	if len(segs) < 2 || (host == "github.com" && len(segs) != 2) {
		return RemoteID{}, errors.New("the address path is not owner/repository")
	}
	return RemoteID{Host: host, Owner: strings.Join(segs[:len(segs)-1], "/"), Repo: segs[len(segs)-1]}, nil
}

// localID names a local repository by its real place: only a trailing /.git is dropped (/x/r.git and /x/r are two
// repositories) and symlinks are resolved.
func localID(path string) (RemoteID, error) {
	clean := strings.TrimSuffix(filepath.Clean(path), "/.git")
	real, err := resolve(clean)
	if err != nil || real == "" || real == "/" {
		return RemoteID{}, errors.New("the local address is not a usable path")
	}
	return RemoteID{Repo: real}, nil
}

// Key is the identity compared and used as a map key: GitHub and GitLab names are case-insensitive, so the owner and
// the repository are lower-cased for comparison (the spelled form stays for display); a local path is compared as is.
func (id RemoteID) Key() RemoteID {
	if id.Host == "" {
		return id
	}
	return RemoteID{Host: id.Host, Owner: strings.ToLower(id.Owner), Repo: strings.ToLower(id.Repo)}
}

// Same reports whether two identities are one repository.
func (id RemoteID) Same(o RemoteID) bool { return id.Key() == o.Key() }

// HTTPSURL is the https address of a hosted repository (a local path is its own address).
func (id RemoteID) HTTPSURL() string {
	if id.Host == "" {
		return id.Repo
	}
	return "https://" + id.Host + "/" + id.Owner + "/" + id.Repo + ".git"
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
				} else if !id.Same(first) {
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
		} else {
			rm.Push = rm.Fetch
			if len(a.pushes) > 0 {
				rm.Push, rm.PushDisabled, err = pushAddress(a.pushes)
				if err != nil {
					fail("a push address", err)
				}
			}
		}
		remotes = append(remotes, rm)
	}
	return remotes, nil
}

// pushAddress reads a remote's push addresses. One that is not an address (the guard DISABLE, no_push) disables
// pushing through the remote: it stays a usable remote, and Roles refuses it only as the fork. A credential is refused.
func pushAddress(pushes []string) (push RemoteID, disabled bool, err error) {
	var first *RemoteID
	for _, u := range pushes {
		id, perr := ParseRemote(u)
		switch {
		case errors.Is(perr, ErrCredential):
			return RemoteID{}, false, perr
		case perr != nil:
			disabled = true
		case first == nil:
			first = &id
		case !id.Same(*first):
			return RemoteID{}, false, errors.New("its push addresses name different repositories")
		}
	}
	if disabled || first == nil {
		return RemoteID{}, true, nil
	}
	return *first, false, nil
}
