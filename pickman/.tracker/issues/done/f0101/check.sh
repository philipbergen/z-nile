#!/usr/bin/env bash
# Acceptance checks for f0101. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0101 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0101"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the hop rises 14 studs and lands in 12 steps on a parabola, 8 steps before the next; airborne mid-step, steps 2 to 11; the shown tick clamped" lune run tests/run -- "$A/jump.spec.luau"
check "AC2: in a session a hop is a per-player intent; airborne, no catch (head-on too), no eat, ghosts move on; a young hop is forgotten when play stops, in the step or between steps, and a hop that reached step 2 is kept; a hop and a shot in one tick both count" lune run tests/run -- "$A/airborne.spec.luau"
check "AC3: walls 9, ghosts 10 by 6, eye 4, clearance 5: ghosts over the walls, the eye under them, the hop's top over both" lune run tests/run -- "$A/heights.spec.luau"
check "AC4: on the classic maze, standing hides the ghosts behind walls and a hop's top shows them" lune run tests/run -- "$A/sight.spec.luau"
check "AC5: the camera shows the server's hop at the shown tick; ghosts GHOST-sized, walls at the scale's height" lune run tests/run -- "$A/place.spec.luau"
check "AC6: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau

finish
