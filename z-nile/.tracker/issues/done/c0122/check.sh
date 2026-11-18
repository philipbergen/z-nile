#!/usr/bin/env bash
# Acceptance checks for c0122. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0122 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0122"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a check.sh flow's real git fetch succeeds whether or not anything is new" \
  lune run tests/run -- "$A/fetch.spec.luau"
check "AC2: a spec run's fetch, a pruning, tag-writing or refspec-writing fetch, a branch update and a remote's removal are still refused, end to end" \
  lune run tests/run -- "$A/refuse.spec.luau"
check "AC3: the zz-test skill, fence.sh and the hook state the fetch rule alike, and the gate scan allows the two end-to-end specs" \
  lune run tests/run -- "$A/wording.spec.luau"
check "AC4: c0131's hook specs and the repo-fence gate spec still pass" \
  lune run tests/run -- tests/acceptance/c0131/accept.spec.luau tests/acceptance/c0131/refuse.spec.luau \
  tests/tooling/repo-fence.spec.luau

finish
