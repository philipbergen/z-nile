//go:build !zn_embed

package payload

// Embedded reports that this binary carries no payload: it was built with a plain go build, not by znbuild.sh.
func Embedded() (Payload, bool) { return Payload{}, false }
