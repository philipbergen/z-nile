package host

import "errors"

// Reason names why a base directory is refused as a host.
type Reason string

// The reasons CheckHost refuses a directory.
const (
	ReasonNotRepo   Reason = "not-a-repository"
	ReasonBare      Reason = "bare-repository"
	ReasonSubmodule Reason = "submodule"
	ReasonNotTop    Reason = "not-top-level"
	ReasonGitfile   Reason = "gitfile"
	ReasonTracked   Reason = "tracked-zn-folder"
)

// UnusualHost is the refusal of a base directory.
type UnusualHost struct {
	Reason Reason
	Detail string
}

func (e *UnusualHost) Error() string { return "host: " + string(e.Reason) + ": " + e.Detail }

// CheckHost refuses a directory that is not the top level of an ordinary clone.
func CheckHost(dir string) error { return errors.New("unimplemented") }
