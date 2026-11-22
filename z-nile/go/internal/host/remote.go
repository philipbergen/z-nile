package host

import "errors"

// RemoteID is a remote repository by what it is, not by how its address is spelled (f0428 step 2).
type RemoteID struct {
	Host  string // lower-case host without port or user; empty for a local path
	Owner string // everything before the repository name ("owner", or "group/subgroup")
	Repo  string // repository name without .git; for a local path, the cleaned absolute path
}

// Remote is one configured remote of the host with its fetch and push addresses.
type Remote struct {
	Name  string
	Fetch RemoteID
	Push  RemoteID
	Err   error // the remote's address could not be used (a credential, an unusable form); Fetch and Push are then empty
}

// ParseRemote turns a remote address into its identity.
func ParseRemote(addr string) (RemoteID, error) { return RemoteID{}, errors.New("unimplemented") }

// Remotes lists the repository's configured remotes, in config order.
func (r *Repo) Remotes() ([]Remote, error) { return nil, errors.New("unimplemented") }
