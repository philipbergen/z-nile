//go:build zn_embed

package payload

import (
	_ "embed"
	"strings"
)

// The build (z-nile/lib/znbuild.sh, through cmd/znpack) writes these three files before it compiles with -tags zn_embed.
//
//go:embed embedded/lune
var luneBytes []byte

//go:embed embedded/engine.tar
var tarBytes []byte

//go:embed embedded/id
var idText string

// Embedded returns the payload compiled into this binary.
func Embedded() (Payload, bool) {
	return Payload{Lune: luneBytes, Tar: tarBytes, ID: strings.TrimSpace(idText)}, true
}
