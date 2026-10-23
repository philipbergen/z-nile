#!/usr/bin/env bash
# Acceptance checks for f0102. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0102 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0102"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: eight sectors from the bearing, ties to the edge, each landing on its edge middle or corner" lune run tests/run -- "$A/sectors.spec.luau"
check "AC2: in-view ghosts listed on request; one glow per sector, lit by the nearest ghost" lune run tests/run -- "$A/glows.spec.luau"
check "AC3: a glow's box hugs the edge, scales with its size and never covers the middle" lune run tests/run -- "$A/box.spec.luau"
check "AC4: one ghost colour table, blue when frightened, white on a flash and for eyes" lune run tests/run -- "$A/colors.spec.luau"
check "AC5: the danger HUD draws glows from Awareness and View, in the safe area under the HUD, with no arrows" lune run tests/run -- "$A/place.spec.luau"
check "AC6: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau

finish
