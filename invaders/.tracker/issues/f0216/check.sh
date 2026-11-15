#!/usr/bin/env bash
# Acceptance checks for f0216. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0216 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0216"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the 5 x 11 formation scores 10/10/20/20/30, steps sideways, advances a row and reverses at a side, and waits one tick per living alien" lune run tests/run -- "$A/formation.spec.luau"
check "AC2: four bunkers of 8 x 6 blocks erode from the side a shot comes from, stop every shot, and are erased by marching aliens" lune run tests/run -- "$A/barriers.spec.luau"
check "AC3: one cannon shot at a time; up to three alien shots, one aimed and two from random living columns, on a score-driven reload; a shot on the cannon costs a life" lune run tests/run -- "$A/shots.spec.luau"
check "AC4: the mystery ship crosses the far end every 25 s, alternating sides, with 8 or more aliens alive, worth 50/100/150/300 by the shot count" lune run tests/run -- "$A/mystery.spec.luau"
check "AC5: 3 lives, a 2 s dying pause, one extra life at 1,500, game over on the last life" lune run tests/run -- "$A/lives.spec.luau"
check "AC6: invasion ends the game at once; a revive gives 3 lives and restarts the wave; each cleared wave starts one row closer, cycling after 8" lune run tests/run -- "$A/waves.spec.luau"
check "AC7: a seeded, deterministic, JSON-safe game at 60 ticks a second" lune run tests/run -- "$A/game.spec.luau"
check "AC8: every Logic feature is engine-free, requires only declared edges and has unit specs" lune run tests/run -- tests/meta/architecture.spec.luau

finish
