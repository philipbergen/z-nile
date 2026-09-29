#!/usr/bin/env bash
# Bootstrap a new host for pickman. Idempotent; safe to re-run. See SETUP.md.
set -euo pipefail
cd "$(dirname "$0")/.."

ROKIT_VERSION=v1.2.0
say() { printf '\n== %s\n' "$1"; }
die() { printf 'SETUP FAILED: %s\n' "$1" >&2; exit 1; }

say "platform"
os=$(uname -s); arch=$(uname -m)
case "$os-$arch" in
  Darwin-arm64) asset=macos-aarch64 ;;
  Darwin-x86_64) asset=macos-x86_64 ;;
  Linux-x86_64) asset=linux-x86_64 ;;
  Linux-aarch64) asset=linux-aarch64 ;;
  *) die "unsupported platform $os-$arch" ;;
esac
echo "$os $arch"

say "prerequisites"
if [[ $os == Darwin ]]; then
  xcode-select -p >/dev/null 2>&1 || die "run: xcode-select --install"
  git --version >/dev/null 2>&1 || die "git unusable; if the Xcode license is not accepted run: sudo xcodebuild -license accept"
fi
for tool in git gh curl unzip; do command -v "$tool" >/dev/null || die "missing $tool"; done
gh auth status >/dev/null 2>&1 || die "run: gh auth login"
echo "git, gh (authenticated), curl, unzip ok"

say "rokit $ROKIT_VERSION"
if ! command -v rokit >/dev/null && [[ ! -x $HOME/.rokit/bin/rokit ]]; then
  tmp=$(mktemp -d)
  gh release download "$ROKIT_VERSION" -R rojo-rbx/rokit -p "rokit-${ROKIT_VERSION#v}-$asset.zip" -D "$tmp"
  unzip -q "$tmp"/*.zip -d "$tmp"
  "$tmp/rokit" self-install
  rm -rf "$tmp"
fi
export PATH="$HOME/.rokit/bin:$PATH"
rokit --version

say "pinned tools (rokit.toml)"
rokit install --no-trust-check
for t in rojo selene stylua luau-lsp lune; do printf '%-9s %s\n' "$t" "$($t --version 2>&1 | head -1)"; done

say "lune type definitions"
lune setup >/dev/null
git checkout -- .luaurc 2>/dev/null || true # lune setup may reorder .luaurc; keep the committed one

say "gate"
scripts/check.sh --full

cat <<'EOF'

SETUP OK.
Optional, for playtesting: install Roblox Studio and the Rojo plugin (Studio > Plugins, or `rojo plugin install`),
then `rojo serve` and click Connect in Studio.
EOF
