#!/usr/bin/env bash
# Acceptance checks for c0137. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0137 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0137"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: no finished check reads .claude from z-nile/, and each rewritten scan goes red on a phrase in either skills folder" \
  lune run tests/run -- "$A/scans.spec.luau"
check "AC2: c0120's finished-file and c0115's absence specs still pass" \
  lune run tests/run -- tests/acceptance/c0120/finished.spec.luau tests/acceptance/c0115/absence.spec.luau

finish
