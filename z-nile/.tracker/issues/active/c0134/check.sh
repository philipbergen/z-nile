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
# AC2: the body of accept.spec (every byte but its header, one run of plain `-- ` comment lines after line 1, cut by
# acceptance/split.luau, the same rule as header.spec; line 1 and the end of the file are body) is what it was where the branch left origin's main. It judges
# the branch's own change only: the base is the merge-base with origin's main tip as `git ls-remote` reports it; on main, and
# on any branch after the change has landed, the base is HEAD or holds the change, and there is nothing to compare
# (design review 001 F2), which it says.
body_unchanged() {
  set -o pipefail
  local f=tests/acceptance/c0131/accept.spec.luau tip base out=.cache/c0134-ac2
  # main's tip as origin itself reports it, never the local refs/remotes/origin/main a branch can move (review 003 F2)
  tip=$(git ls-remote origin refs/heads/main | awk '{print $1}') && [[ -n $tip ]] ||
    { echo "cannot read origin's main (git ls-remote origin)"; return 1; }
  git cat-file -e "$tip^{commit}" 2>/dev/null || { echo "origin's main $tip is not here: git fetch origin"; return 1; }
  base=$(git merge-base "$tip" HEAD) || { echo "no merge-base with origin's main"; return 1; }
  [[ $base != "$(git rev-parse HEAD)" ]] || echo "base is HEAD: nothing to compare"
  git cat-file -e "$base:z-nile/$f" || { echo "$f is not at the base $base"; return 1; }
  # each body is written by a command whose status is checked: a body.luau that can't run is red, never "equal" (003 F1)
  rm -rf "$out" && mkdir -p "$out" || return 1
  git show "$base:z-nile/$f" | lune run "$A/body.luau" >"$out/base" || { echo "cannot cut the base's body"; return 1; }
  lune run "$A/body.luau" <"$f" >"$out/now" || { echo "cannot cut the working file's body"; return 1; }
  cmp -s "$out/base" "$out/now" || { diff "$out/base" "$out/now"; echo "$f changed below its header"; return 1; }
}
check "AC2: below its header, accept.spec is unchanged (a comment-only change)" body_unchanged
check "AC3: both c0131 specs still pass" \
  lune run tests/run -- tests/acceptance/c0131/accept.spec.luau tests/acceptance/c0131/refuse.spec.luau

finish
