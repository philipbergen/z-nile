#!/usr/bin/env bash
# Acceptance checks for c0159. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0159 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0159"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: d0105's, f0033's, f0102's and c0106's specs are exactly the narrowed ones (each pinned whole) and their check.sh files still run them; every case of the three DangerHud specs passes on today's DangerHud, on one that draws f0158's ring and on four correct variants of it; and five regressions of the ring DangerHud each still fail the case that pins it" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC2: d0105's, f0033's, f0102's and c0106's acceptance checks pass" bash -c 'bash "$("$ZN_ROOT/zn" find d0105)/check.sh" && bash "$("$ZN_ROOT/zn" find f0033)/check.sh" && bash "$("$ZN_ROOT/zn" find f0102)/check.sh" && bash "$("$ZN_ROOT/zn" find c0106)/check.sh"'

finish
