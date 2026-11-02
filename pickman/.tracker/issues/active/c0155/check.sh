#!/usr/bin/env bash
# Acceptance checks for c0155. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0155 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0155"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: f0110's Touch.buttons case and f0146's button-map case pin each of today's entries, pass with an added button and fail when any pinned entry moves or is missing, every added pad button has an action of its own, and their check.sh files still run them" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC2: f0110's and f0146's acceptance checks pass" bash -c 'bash "$("$ZN_ROOT/zn" find f0110)/check.sh" && bash "$("$ZN_ROOT/zn" find f0146)/check.sh"'

finish
