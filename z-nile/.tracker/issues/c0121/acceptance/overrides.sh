#!/usr/bin/env bash
# c0121 AC7: each overridden spec is the file as the branch's merge base with main had it plus the reviewed hunks
# (overrides.patch) and nothing else, so main's later work on the same files is the merge's to judge, not this check's.
# SEQUESTERED. Usage: overrides.sh [<main tip>]  (default: the tip of origin's main, read from origin itself; unreadable or
# not local = red). It trusts the origin it resolves: a url.*.insteadOf or remote set-url feeds it any main (detect, not
# prevent), so check.sh prints the resolved URL beside the verdict.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TOP="$(git -C "$HERE" rev-parse --show-toplevel)"
TIP="${1:-$(git -C "$TOP" ls-remote origin refs/heads/main | cut -f1)}"
[[ -n $TIP ]] || { echo "AC7: the tip of origin's main is unreadable" >&2; exit 1; }
git -C "$TOP" cat-file -e "$TIP^{commit}" || { echo "AC7: main's tip $TIP is not in this repository: fetch origin" >&2; exit 1; }
# the last commit of main the branch has: its delta is what the patch must explain
if git -C "$TOP" merge-base --is-ancestor HEAD "$TIP"; then
	echo "AC7: HEAD is already part of main $TIP: there is no branch delta to judge (an unimplemented tree must not pass)" >&2
	exit 1
fi
BASE="$(git -C "$TOP" merge-base HEAD "$TIP")" || { echo "AC7: HEAD and main $TIP share no history" >&2; exit 1; }
PATCH="$HERE/overrides.patch"
[[ -s $PATCH ]] || { echo "AC7: overrides.patch is missing or empty" >&2; exit 1; }
FILES=(
	z-nile/tests/acceptance/c0118/docs.spec.luau
)
mkdir -p "$TOP/z-nile/.cache"
TMP="$(mktemp -d "$TOP/z-nile/.cache/c0121-ac7.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# a repository of its own, so git apply works from its top and never reaches the real one
git -C "$TMP" init -q
for f in "${FILES[@]}"; do
	mkdir -p "$TMP/$(dirname "$f")"
	git -C "$TOP" show "$BASE:$f" >"$TMP/$f"
done
git -C "$TMP" apply "$PATCH" || { echo "AC7: the reviewed hunks no longer apply to the merge base $BASE with main $TIP" >&2; exit 1; }
bad=0
for f in "${FILES[@]}"; do
	cmp -s "$TMP/$f" "$TOP/$f" || { echo "AC7: differs from the merge base plus the reviewed hunks: $f" >&2; bad=1; }
done
# and it changes no other test file (design review 006 F2, 007 F2): its changes since the merge base, in the working tree,
# under every project's tests/ list only the two files c0121 owns, each modified in place with its mode unchanged; no
# rename shows as only its destination (--no-renames), nothing is new or untracked (c0121's promoted folder does not exist
# until `done`), and a git failure is red. The reads go into variables, so a failing git is not an empty list.
OWNED=(
	z-nile/tests/acceptance/c0118/docs.spec.luau
	z-nile/tests/lib/cachepaths.luau
)
RAW="$(git -C "$TOP" diff --no-renames --raw "$BASE" -- ':(glob)*/tests/**')" || { echo "AC7: git diff against the merge base failed" >&2; exit 1; }
NEW="$(git -C "$TOP" ls-files -o --exclude-standard -- ':(glob)*/tests/**')" || { echo "AC7: git ls-files failed" >&2; exit 1; }
if [[ -n $NEW ]]; then
	echo "AC7: untracked files under tests/ (c0121 adds none before done): $NEW" >&2
	bad=1
fi
while IFS=$'\t' read -r meta f; do
	[[ -n $meta ]] || continue
	owned=0
	for o in "${OWNED[@]}"; do [[ $f == "$o" ]] && owned=1; done
	read -r om nm _ _ st <<<"${meta#:}"
	if [[ $owned == 1 && $st == M && $om == "$nm" ]]; then continue; fi
	echo "AC7: changes a test file it does not own, or not in place ($st $om $nm): $f" >&2
	bad=1
done <<<"$RAW"
exit $bad
