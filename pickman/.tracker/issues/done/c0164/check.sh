#!/usr/bin/env bash
# Acceptance checks for c0164. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0164 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0164"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: R0056's main-walls spec is narrowed to where the calls sit, and f0126's views.spec is exactly f0126's with c0164's every-frame walls-and-radar case added, which passes" lune run tests/run -- "$A/walls.spec.luau"
check "AC2: f0126's and f0109's acceptance checks pass" bash -c 'bash "$("$ZN_ROOT/zn" find f0126)/check.sh" && bash "$("$ZN_ROOT/zn" find f0109)/check.sh"'

finish
