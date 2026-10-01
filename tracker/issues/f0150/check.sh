#!/usr/bin/env bash
# Acceptance checks for f0150. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0150 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0150"

check "AC1: Pellets: the pellets of a maze, eating, reset, points and stall distance" lune run tests/run -- "$A/pellets.spec.luau"
check "AC2: walking eats each pellet once on tile entry and scores it" lune run tests/run -- "$A/eating.spec.luau"
check "AC3: eating pauses the player as in the arcade: 15 units a pellet, 45 a power pellet" lune run tests/run -- "$A/slowdown.spec.luau"
check "AC4: the last pellet clears the level; the next level resets pellets and player and runs faster" lune run tests/run -- "$A/level.spec.luau"

finish
