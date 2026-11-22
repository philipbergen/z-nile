#!/usr/bin/env bash
# Builds the zn program with its Lune and engine embedded (f0427): znbuild.sh --out <binary> [options]
#   --goos <os> --goarch <arch>   the target (default: this machine's, from `go env`)
#   --lune <file>                 a Lune binary, for a target whose cmd/zn/lune.sum entry is a bin (darwin-aarch64:
#                                 default is the one rokit installed, ~/.rokit/tool-storage/lune-org/lune/0.10.5/lune)
#   --lune-zip <file>             the Lune release zip, for a target whose entry is a zip (linux-x86_64)
#   --checkout <dir>              the checkout whose z-nile/ engine is packed (default: this script's)
#   --go-dir <dir>                the Go module to build in (default: <checkout>/z-nile/go); the embedded files are
#                                 written under its internal/payload/embedded, which git ignores
#   --sum <file>                  lune.sum (default: <go-dir>/cmd/zn/lune.sum)
# The Lune is checked against lune.sum before it is embedded; a target with no Lune supplied, or one that does not match,
# fails with one message and builds nothing. The binary is built beside --out and renamed onto it. Nothing is downloaded.
# Exit 2: usage, no Lune supplied or a Lune that does not match; 3: no usable Go; 1: the build failed.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$here/goenv.sh"
out="" goos="" goarch="" lune="" zip="" checkout="$(cd "$here/../.." && pwd -P)" godir="" sum=""
while [[ $# -gt 0 ]]; do
  case $1 in
  --out) out=${2:?--out needs a path}; shift 2 ;;
  --goos) goos=${2:?}; shift 2 ;;
  --goarch) goarch=${2:?}; shift 2 ;;
  --lune) lune=${2:?}; shift 2 ;;
  --lune-zip) zip=${2:?}; shift 2 ;;
  --checkout) checkout=${2:?}; shift 2 ;;
  --go-dir) godir=${2:?}; shift 2 ;;
  --sum) sum=${2:?}; shift 2 ;;
  *) echo "znbuild.sh: unknown argument $1 (see the header of z-nile/lib/znbuild.sh)" >&2; exit 2 ;;
  esac
done
[[ -n $out ]] || { echo "znbuild.sh: --out <binary> is required" >&2; exit 2; }
case $(go_status || true) in
absent) echo "znbuild.sh: no Go toolchain (SETUP.md)" >&2; exit 3 ;;
old) echo "znbuild.sh: Go 1.24 or newer is needed (SETUP.md)" >&2; exit 3 ;;
esac
[[ -n $godir ]] || godir="$checkout/z-nile/go"
[[ -n $sum ]] || sum="$godir/cmd/zn/lune.sum"
[[ -n $goos ]] || goos=$(go env GOHOSTOS)
[[ -n $goarch ]] || goarch=$(go env GOHOSTARCH)
case $goarch in amd64) arch=x86_64 ;; arm64) arch=aarch64 ;; *) arch=$goarch ;; esac
platform="$goos-$arch"
rokit_lune="$HOME/.rokit/tool-storage/lune-org/lune/0.10.5/lune"
if [[ $platform == darwin-aarch64 && -z $lune && -f $rokit_lune ]]; then
  lune=$rokit_lune
fi
embedded="$godir/internal/payload/embedded"
rm -rf "$embedded"
packargs=(-root "$checkout" -sum "$sum" -platform "$platform" -out "$embedded")
[[ -z $lune ]] || packargs+=(-lune "$lune")
[[ -z $zip ]] || packargs+=(-zip "$zip")
# the host's own toolchain runs the packer, whatever the target is
if ! (cd "$godir" && env -u GOOS -u GOARCH -u CGO_ENABLED go run -buildvcs=false ./cmd/znpack "${packargs[@]}"); then
  rm -rf "$embedded"
  exit 2
fi
id=$(cat "$embedded/id")
mkdir -p "$(dirname "$out")"
tmp=$(mktemp "$out.XXXXXX")
if ! (cd "$godir" && CGO_ENABLED=0 GOOS=$goos GOARCH=$goarch go build -buildvcs=false -tags zn_embed -trimpath -ldflags "-s -w -X main.build=$id" -o "$tmp" ./cmd/zn); then
  rm -f "$tmp"
  exit 1
fi
chmod 755 "$tmp"
mv -f "$tmp" "$out"
echo "zn $id built for $platform: $out"
