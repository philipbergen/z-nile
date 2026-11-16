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
check "AC1: the danger ring is eight sectors of six translucent dots on one circle centred in its frame, 60% of the frame's smaller side across, lit only toward dangerous ghosts, with the user's opacities" lune run tests/run -- "$A/ring.spec.luau"
check "AC2: measured in the frames the game draws them in, on every f0029 sample and the short screens under a top bar, desktop and touch, no ring dot overlaps the HUD blocks, the radar, the snap control, f0110's FIRE and HOP buttons, f0126's PICK button or the jump buttons, except overlaps the user accepted" env F0158_EXACT=1 lune run tests/run -- "$A/clear.spec.luau"
check "AC3: DangerHud's real source draws the ring Awareness computes in the core-UI safe area, in the one warning colour at the decided opacities, reusing its frames, under the HUD, and the edge glows are gone" lune run tests/run -- "$A/place.spec.luau"
check "AC4: the warning colour is a red with contrast at least 2.5 against the maze blue, the edible green, the white flash and the marked walls' gold" lune run tests/run -- "$A/colors.spec.luau"

finish
