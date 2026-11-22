//go:build zn_embed

package payload

import _ "embed"

// The build (z-nile/lib/znbuild.sh, through cmd/znpack) writes these three files before it compiles with -tags zn_embed.
//
//go:embed embedded/lune
var luneBytes []byte

//go:embed embedded/engine.tar
var tarBytes []byte

//go:embed embedded/meta
var metaText string

// Embedded returns the payload compiled into this binary, its id computed from its bytes.
func Embedded() (Payload, bool) { return New(luneBytes, tarBytes, metaText), true }
