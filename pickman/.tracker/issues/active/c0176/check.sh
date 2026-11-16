#!/usr/bin/env bash
# Acceptance checks for c0176. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0176 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0176"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: f0023's session-ghosts, f0100's drops and shots, f0101's airborne and c0153's golden specs are exactly the narrowed ones (each pinned whole), every session the four build takes the shipped config less its ramp, and their check.sh files still run them" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC2: f0023's, f0100's, f0101's and c0153's acceptance checks pass" bash -c 'bash "$("$ZN_ROOT/zn" find f0023)/check.sh" && bash "$("$ZN_ROOT/zn" find f0100)/check.sh" && bash "$("$ZN_ROOT/zn" find f0101)/check.sh" && bash "$("$ZN_ROOT/zn" find c0153)/check.sh"'

finish
