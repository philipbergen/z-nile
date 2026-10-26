#!/usr/bin/env bash
# Acceptance checks for c0134. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0134 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0134"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: accept.spec's header describes its two acceptances and leaves the refusals to refuse.spec" \
  lune run tests/run -- "$A/header.spec.luau"
# AC2: everything from accept.spec's first line of code on is what it was where the branch left origin/main (a
# comment-only change). The base is the merge-base with origin/main, which the branch can't move; once the change has
# landed the base is HEAD's own ancestor and the comparison holds by construction.
body_unchanged() {
  local f=tests/acceptance/c0131/accept.spec.luau base
  base=$(git merge-base origin/main HEAD) || { echo "no merge-base with origin/main"; return 1; }
  git cat-file -e "$base:z-nile/$f" || { echo "$f is not at the base $base"; return 1; }
  diff <(git show "$base:z-nile/$f" | awk 'f||/^local /{f=1; print}') <(awk 'f||/^local /{f=1; print}' "$f") ||
    { echo "$f changed below its header"; return 1; }
}
check "AC2: below its header, accept.spec is unchanged (a comment-only change)" body_unchanged
check "AC3: both c0131 specs still pass" \
  lune run tests/run -- tests/acceptance/c0131/accept.spec.luau tests/acceptance/c0131/refuse.spec.luau

finish
