#!/usr/bin/env bash
# Acceptance checks for f0109. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0109 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0109"

check "AC1: Inky is lemon and stands out against the walls, the floor, the ghosts, the pellets and the shots" lune run tests/run -- "$A/colors.spec.luau" "$A/place.spec.luau"
check "AC2: the other ghosts and the frightened, blinking and eyes looks are unchanged" lune run tests/run -- "$A/colors.spec.luau"
check "AC3: walls are blue, green while edible, white in the level-clear flash; every dangerous ghost stands out on green" lune run tests/run -- "$A/colors.spec.luau"
check "AC4: the ghosts are edible exactly while the power timer runs" lune run tests/run -- "$A/colors.spec.luau"
check "AC5: MazeView's real source and the radar paint the walls by View.wallColor, from the state Main hands them" lune run tests/run -- "$A/place.spec.luau"
check "AC6: game-design.md records the decision and no longer asks for Inky's colour" lune run tests/run -- "$A/docs.spec.luau"

finish
