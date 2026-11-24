#!/usr/bin/env bash
# Acceptance checks for c0228. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0228 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0228"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: View.runsKey keys equal walls equally and walls that differ in any run's bounds, mark or count differently" lune run tests/run -- "$A/runs.spec.luau"
check "AC2: MazeView builds with the marks and redraws only walls it has not drawn; Main builds every wall once per maze and once per change" lune run tests/run -- "$A/walls.spec.luau"
check "AC3: f0126's views and adapters specs, f0109's place and colors specs, c0164's walls spec and tests/place/main-walls still pass" lune run tests/run -- tests/acceptance/f0126/views.spec.luau tests/acceptance/f0126/adapters.spec.luau tests/acceptance/f0109/place.spec.luau tests/acceptance/f0109/colors.spec.luau tests/acceptance/c0164/walls.spec.luau tests/place/main-walls.spec.luau

finish
