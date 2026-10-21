#!/usr/bin/env bash
# Acceptance checks for f0029. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0029 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0029"

check "AC1: zero insets match today's Hud.layout, a real inset only moves the safe rect, and safeInset pins the cutout" lune run tests/run -- "$A/layout.spec.luau"
check "AC2: the snap button is at least 44 px, the samples miss the forward view, and the narrow box overlaps lives" lune run tests/run -- "$A/button.spec.luau"
check "AC3: HudView reads GetInsetArea through Hud.safeInset and does not read GetGuiInset" lune run tests/run -- "$A/place.spec.luau"
check "AC4: one phone-sized session swipes, looks, snaps and keeps the HUD readable" lune run tests/run -- "$A/phone.spec.luau"
check "AC5: on a touch screen the radar, the power bar and the snap button miss Roblox's jump button corner" lune run tests/run -- "$A/jump.spec.luau"

finish
