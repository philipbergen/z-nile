#!/usr/bin/env bash
# Acceptance checks for f0158. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0158 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0158"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the danger ring is eight sectors of translucent dots on one circle centred on the screen, 60% of its smaller side across, lit per sector from the glows" lune run tests/run -- "$A/ring.spec.luau"
check "AC2: on desktop and touch, landscape and portrait, no ring dot overlaps the HUD blocks, the radar, the snap control or the jump buttons" lune run tests/run -- "$A/clear.spec.luau"
check "AC3: DangerHud draws the ring Awareness computes, in each ghost's colour, under the HUD, and the edge glows are gone" lune run tests/run -- "$A/place.spec.luau"

finish
