#!/usr/bin/env bash
# c0118 AC9: each overridden spec is main's file plus the reviewed hunks (overrides.patch) and nothing else. SEQUESTERED.
# Usage: overrides.sh [<main tip>]  (default: the tip of origin's main, read from origin itself; unreadable or not local = red)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"
TIP="${1:-$(git -C "$TOP" ls-remote origin refs/heads/main | cut -f1)}"
[[ -n $TIP ]] || { echo "AC9: the tip of origin's main is unreadable" >&2; exit 1; }
git -C "$TOP" cat-file -e "$TIP^{commit}" || { echo "AC9: main's tip $TIP is not in this repository: fetch origin" >&2; exit 1; }
PATCH="$HERE/overrides.patch"
[[ -s $PATCH ]] || { echo "AC9: overrides.patch is missing or empty" >&2; exit 1; }
FILES=(
	z-nile/tests/acceptance/c0042/model.spec.luau
	z-nile/tests/acceptance/c0042/smoke.spec.luau
	z-nile/tests/acceptance/c0107/keep.spec.luau
	z-nile/tests/acceptance/c0107/page.spec.luau
	z-nile/tests/acceptance/c0107/views.spec.luau
	z-nile/tests/acceptance/c0115/readme.spec.luau
	z-nile/tests/acceptance/c0172/narrowed.spec.luau
	z-nile/tests/tooling/board.spec.luau
)
mkdir -p "$TOP/z-nile/.cache"
TMP="$(mktemp -d "$TOP/z-nile/.cache/c0118-ac9.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# a repository of its own, so git apply works from its top and never reaches the real one
git -C "$TMP" init -q
for f in "${FILES[@]}"; do
	mkdir -p "$TMP/$(dirname "$f")"
	git -C "$TOP" show "$TIP:$f" >"$TMP/$f"
done
git -C "$TMP" apply "$PATCH" || { echo "AC9: the reviewed hunks no longer apply to main's $TIP" >&2; exit 1; }
bad=0
for f in "${FILES[@]}"; do
	cmp -s "$TMP/$f" "$TOP/$f" || { echo "AC9: differs from main plus the reviewed hunks: $f" >&2; bad=1; }
done
exit $bad
