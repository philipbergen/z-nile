#!/usr/bin/env bash
# Acceptance checks for f0125. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0125 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0125"

check "AC1: the shipped config's edge over a hunting ghost is the classic edge times 1.07 to 1.13 on every level" lune run tests/run -- "$A/speeds.spec.luau"
check "AC2: the default config keeps the classic tables" lune run tests/run -- "$A/speeds.spec.luau"
check "AC3: eyes keep twice level 1's speed; the player stays within a tile a tick" lune run tests/run -- "$A/speeds.spec.luau"
check "AC4: a shipped session's ghosts run at the speeds Session.speeds gives" lune run tests/run -- "$A/speeds.spec.luau"
check "AC5: a bad ghostTuning is refused" lune run tests/run -- "$A/speeds.spec.luau"
check "AC6: game-design.md records the user's factor and where it lives" lune run tests/run -- "$A/docs.spec.luau"

finish
