#!/usr/bin/env bash
# Builds the live layer's binary: gobuild.sh <checkout> <out>. The sources are <checkout>/z-nile/go; the binary is
# built into a temporary file beside <out> and renamed into place, so a running daemon never sees half a file. The
# build id (the first 12 hex of the sources' sha256) is stamped into it. Go's build cache is <out>'s .cache/go-build.
# Prints one line. Exit 3 when Go is absent or there are no sources.
set -euo pipefail
src="$1/z-nile/go"
out="$2"
if ! command -v go >/dev/null 2>&1; then
  echo "live layer unavailable: no Go toolchain and no built znlive (install Go: SETUP.md)" >&2
  exit 3
fi
if [[ ! -f $src/go.mod ]]; then
  echo "live layer unavailable: no Go sources at $src" >&2
  exit 3
fi
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; }
id=$(cd "$src" && find . \( -name '*.go' -o -name go.mod \) -type f | LC_ALL=C sort | while IFS= read -r f; do
  printf '%s\n' "$f"
  cat "$f"
done | sha | cut -c1-12)
mkdir -p "$(dirname "$out")"
cache="$(cd "$(dirname "$out")/.." && pwd -P)/go-build"
tmp=$(mktemp "$out.XXXXXX")
if ! (cd "$src" && GOCACHE="$cache" go build -ldflags "-X main.build=$id" -o "$tmp" ./cmd/znlive); then
  rm -f "$tmp"
  exit 1
fi
chmod 755 "$tmp"
mv -f "$tmp" "$out"
echo "znlive $id built: $out"
