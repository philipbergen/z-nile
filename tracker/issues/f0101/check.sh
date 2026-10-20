#!/usr/bin/env bash
# Acceptance checks for f0101. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0101 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0101"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: the jump rises 14 studs and lands in 0.8 s on a parabola, then 0.5 s before the next" lune run tests/run -- "$A/jump.spec.luau"
check "AC2: walls 9, ghosts 10 by 6, eye 4: ghosts over the walls, the eye under them, the jump's top over both" lune run tests/run -- "$A/heights.spec.luau"
check "AC3: on the classic maze, standing hides the ghosts behind walls and a jump's top shows them" lune run tests/run -- "$A/sight.spec.luau"
check "AC4: the camera jumps and lifts the eye; ghosts are drawn GHOST-sized" lune run tests/run -- "$A/place.spec.luau"
check "AC5: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau

finish
