#!/usr/bin/env bash
# Acceptance checks for c0380. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0380 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0380"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: d0124's, f0026's and f0145's board pins that f0186 changes are exactly the narrowed ones (each pinned whole, with c0128's pin of f0026's adapters.spec), every board text they compared exactly is compared up to the level, nothing f0186 removes is pinned, and their check.sh files still run them" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC2: d0124's, f0026's, f0145's and c0128's acceptance checks pass" bash -c 'bash "$("$ZN_ROOT/zn" find d0124)/check.sh" && bash "$("$ZN_ROOT/zn" find f0026)/check.sh" && bash "$("$ZN_ROOT/zn" find f0145)/check.sh" && bash "$("$ZN_ROOT/zn" find c0128)/check.sh"'

finish
