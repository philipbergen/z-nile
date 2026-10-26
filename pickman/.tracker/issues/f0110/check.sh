#!/usr/bin/env bash
# Acceptance checks for f0110. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0110 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0110"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the hop button is Roblox's legacy jump button, the fire button sits one margin left of it clear of the snap control, and on every sample both are at least 44 px and miss the HUD and the radar (but for the pinned overlaps)" lune run tests/run -- "$A/buttons.spec.luau"
check "AC2: in Touch's fold a finger down on the fire or hop button acts once at once and never looks or turns, one finger per zone, snap then fire then hop then the halves, and without the new rectangles the fold is unchanged" lune run tests/run -- "$A/fold.spec.luau"
check "AC3: Controls sends the aimed shot for a fire tap and Hop.INTENT for a hop tap from the hook's rectangles, HudView draws non-active outlined FIRE and JUMP discs under its Hud ScreenGui on touch screens at Touch.buttons and reports them, and Main wires HudView.buttons" lune run tests/run -- "$A/adapters.spec.luau"
check "AC4: end to end on a phone, a dropped shot, a look drag and a fire tap eat the ghost on the right, and a hop tap starts the hop" lune run tests/run -- "$A/hunt.spec.luau"
check "AC5: the existing touch, key, HUD, blaster and hop specs still pass" lune run tests/run -- tests/acceptance/f0027/*.spec.luau tests/acceptance/f0028/*.spec.luau tests/acceptance/f0029/*.spec.luau tests/acceptance/f0100/*.spec.luau tests/acceptance/f0101/*.spec.luau tests/acceptance/f0104/*.spec.luau tests/unit/Touch/*.spec.luau tests/place/touch-adapters.spec.luau tests/place/hud-shots.spec.luau
check "AC6: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau

finish
