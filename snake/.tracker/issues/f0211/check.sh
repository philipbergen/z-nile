#!/usr/bin/env bash
# Acceptance checks for f0211. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0211 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0211"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: each map's arena: the side for N players, speed, goal, k-1 walls that never connect, clear spawns, map 2 near the middle, a seeded roll that grows by 2" \
  lune run tests/run -- "$A/maps.spec.luau"
check "AC2: movement: the Ready, one tile per step at the map's speed, Left and Right with two buffered turns, time cut any way, real frame rates included" \
  lune run tests/run -- "$A/moves.spec.luau"
check "AC3: apples: players + 1 on free tiles, +1 length at once, 10 x map points, topped up whenever one is eaten, none on a full board" \
  lune run tests/run -- "$A/food.spec.luau"
check "AC4: deaths on the border, walls and bodies, heads meeting kill both, 3 lives, 1.5 s wait, safest respawn, 2 s Ready, dying and out bodies off the board" \
  lune run tests/run -- "$A/deaths.spec.luau"
check "AC5: the goal length clears the map: 2 s MAP CLEAR, 100 x k, the next map with one more wall, reset snakes, more speed" \
  lune run tests/run -- "$A/progress.spec.luau"
check "AC6: played end to end: a bot clears maps 1 to 4, and a four-snake game keeps the board consistent" \
  lune run tests/run -- "$A/play.spec.luau"

finish
