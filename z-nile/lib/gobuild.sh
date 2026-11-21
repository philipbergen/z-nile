#!/usr/bin/env bash
# Builds the live layer's binary: gobuild.sh <checkout> <out>. The sources are <checkout>/z-nile/go. The build id (the
# first 12 hex of the sha256 of the non-test Go sources, go.mod and the Go version) is kept beside the binary, in
# <out>.id, and an unchanged id skips the build and the rename: a replaced binary restarts a running daemon. A build
# goes to a temporary file beside <out> and is renamed into place. Go's build cache is <out>'s .cache/go-build.
# Prints one line. Exit 3 when Go is absent or older than 1.24, or there are no sources.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/goenv.sh"
src="$1/z-nile/go"
out="$2"
case $(go_status || true) in
absent)
  echo "live layer unavailable: no Go toolchain and no built znlive (install Go: SETUP.md)" >&2
  exit 3
  ;;
old)
  echo "live layer unavailable: Go 1.24 or newer is needed (SETUP.md)" >&2
  exit 3
  ;;
esac
if [[ ! -f $src/go.mod ]]; then
  echo "live layer unavailable: no Go sources at $src" >&2
  exit 3
fi
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }
id=$({
  go env GOVERSION
  cd "$src" && find . \( -name '*.go' -o -name go.mod \) -type f ! -name '*_test.go' | LC_ALL=C sort | while IFS= read -r f; do
    printf '%s\n' "$f"
    cat "$f"
  done
} | sha | cut -c1-12)
if [[ -f $out && -f $out.id && "$(cat "$out.id")" == "$id" ]]; then
  echo "znlive $id up to date: $out"
  exit 0
fi
mkdir -p "$(dirname "$out")"
cache="$(cd "$(dirname "$out")/.." && pwd -P)/go-build"
tmp=$(mktemp "$out.XXXXXX")
if ! (cd "$src" && GOCACHE="$cache" go build -ldflags "-X main.build=$id" -o "$tmp" ./cmd/znlive); then
  rm -f "$tmp"
  exit 1
fi
chmod 755 "$tmp"
mv -f "$tmp" "$out"
idtmp=$(mktemp "$out.id.XXXXXX")
echo "$id" >"$idtmp"
mv -f "$idtmp" "$out.id"
echo "znlive $id built: $out"
