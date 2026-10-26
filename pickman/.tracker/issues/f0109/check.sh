#!/usr/bin/env bash
# Acceptance checks for f0109. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0109 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0109"

check "AC1: Inky is its own yellow and stands out against walls, edible walls, floor, ghosts, pellets and shots" lune run tests/run -- "$A/colors.spec.luau"
check "AC2: the other ghosts and the frightened, blinking and eyes looks are unchanged" lune run tests/run -- "$A/colors.spec.luau"
check "AC3: walls are blue, green while edible, white in the level-clear flash, which wins" lune run tests/run -- "$A/colors.spec.luau"
check "AC4: the ghosts are edible exactly while the power timer runs" lune run tests/run -- "$A/colors.spec.luau"
check "AC5: MazeView paints by View.wallColor and Main tells it when the ghosts are edible" lune run tests/run -- "$A/place.spec.luau"

finish
