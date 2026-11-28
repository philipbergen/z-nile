#!/usr/bin/env bash
# Acceptance checks for f0214. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0214 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0214"

check "AC1: boost doubles speed, sheds 1 segment every 0.5 s into a crumb (never below 4), validates inputs, and is frame-rate independent" \
  lune run tests/run -- "$A/boost.spec.luau"
check "AC2: golden apple spawns every 20 s for 6 s on a free tile, gives +3 length and 50 x map points, pauses in MAP CLEAR, and is frame-rate independent" \
  lune run tests/run -- "$A/golden.spec.luau"
check "AC3: crumbs drop on every other segment on shared-arena death (not solo), give +1 length and 5 points flat, stay disjoint, and clear on respawn/map start" \
  lune run tests/run -- "$A/crumbs.spec.luau"
check "AC4: boost, golden apples, and crumbs work together in multi-snake play with all board invariants intact" \
  lune run tests/run -- "$A/integration.spec.luau"

finish
