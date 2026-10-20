#!/usr/bin/env bash
# Acceptance checks for d0105. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/d0105 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0105"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: Hud.radarBox is the bottom-right square, inset by the margin on the right and by the bar height plus two margins on the bottom" lune run tests/run -- "$A/radar.spec.luau"
check "AC2: on a screen at least 480 by 320 the 120-pixel radar is inside the right half, a margin above the power bar, and clear of the lives and the level" lune run tests/run -- "$A/radar.spec.luau"
check "AC3: DangerHud places the radar from Hud.radarBox of the current screen before a snapshot is required, keeps the default anchor, and does not turn a CoreGui off" lune run tests/run -- "$A/adapter.spec.luau"
check "AC4: Hud.layout and the existing HUD and danger-adapter specs still pass" lune run tests/run -- tests/unit/Hud/hud.spec.luau tests/acceptance/f0019/layout.spec.luau tests/acceptance/f0019/place.spec.luau tests/acceptance/f0019/hud.spec.luau tests/acceptance/f0033/adapters.spec.luau

finish
