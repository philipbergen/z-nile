#!/usr/bin/env bash
# Acceptance checks for d0296. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0296 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0296"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
SPECS=(tests/acceptance/c0074/done-gate.spec.luau tests/acceptance/c0080/consequences.spec.luau tests/acceptance/c0120/promote-home.spec.luau)
check "AC1: the three clone-fixture specs pass (the raft's worktree is on a layer branch)" lune run tests/run -- "${SPECS[@]}"
named() {
  local rc=0 f
  for f in "${SPECS[@]}"; do
    grep -qF -- '"checkout", "-q", "-B", "main"' "$f" || { echo "$f does not name its fixture's branch main"; rc=1; }
  done
  return $rc
}
check "AC2: each of the three fixtures names its branch main after the clone" named

finish
