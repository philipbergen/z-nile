#!/usr/bin/env bash
# Builds the live layer's binary: gobuild.sh <checkout> <out>. The sources are <checkout>/z-nile/go. The build id (the
# first 12 hex of the sha256 of the non-test Go sources, go.mod and the Go version) is kept beside the binary, in
# <out>.id, and an unchanged id skips the build and the rename: a replaced binary restarts a running daemon. A build
# goes to a temporary file beside <out> and is renamed into place. Go's build cache is <out>'s .cache/go-build.
# Prints one line. Exit 3 when Go is absent or older than 1.24, or there are no sources.
# gobuild.sh <checkout> <out> [--auto]: --auto is `./zn live <op>`'s rebuild. A failed build writes its source id to <out>.failed
# and, in --auto, the compiler's output is not printed; while the sources' id equals the recorded one an --auto call does not
# try again (exit 4, silent). A plain call (`./zn live build`, the gate) always builds and prints the compiler's output. Exit
# 1: the build failed; 4: skipped for a failure already recorded.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/goenv.sh"
src="$1/z-nile/go"
out="$2"
auto=""
[[ ${3:-} == --auto ]] && auto=1
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
  touch "$out.id" # the id file's time says "checked now" (zn live rebuilds when a source is newer); the binary stays as it is
  echo "znlive $id up to date: $out"
  exit 0
fi
if [[ -n $auto && -f $out.failed && "$(head -n1 "$out.failed")" == "$id" ]]; then
  exit 4
fi
mkdir -p "$(dirname "$out")"
cache="$(cd "$(dirname "$out")/.." && pwd -P)/go-build"
tmp=$(mktemp "$out.XXXXXX")
if ! built=$(cd "$src" && GOCACHE="$cache" go build -ldflags "-X main.build=$id" -o "$tmp" ./cmd/znlive 2>&1); then
  rm -f "$tmp"
  { echo "$id"; echo "$built"; } >"$out.failed"
  [[ -n $auto ]] || echo "$built" >&2
  exit 1
fi
rm -f "$out.failed"
chmod 755 "$tmp"
mv -f "$tmp" "$out"
idtmp=$(mktemp "$out.id.XXXXXX")
echo "$id" >"$idtmp"
mv -f "$idtmp" "$out.id"
echo "znlive $id built: $out"
