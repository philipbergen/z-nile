#!/usr/bin/env bash
# Acceptance checks for c0414. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0414 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0414"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# ./zn find answers from the project home, where ac.sh runs this; the rule script takes folders from the checkout's top
D="$("$ZN_ROOT/zn" find d0297)"
R="$("$ZN_ROOT/zn" find R0133)"
check "AC1: c0120's finished rule reports no path in d0297's check.sh" lune run "$R/finished-rule.luau" "$(basename "$PWD")/$D"
check "AC2: d0297's check.sh passes" bash "$D/check.sh"

finish
