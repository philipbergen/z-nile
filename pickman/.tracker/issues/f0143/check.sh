#!/usr/bin/env bash
# Acceptance checks for f0143. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0143 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0143"

check "AC1: Boost's constants, start, span, cooldown, capped and rounded speed, status, double tap and FOV ramp; on every level a boost gains two tiles on a hunting ghost within a tile a step" lune run tests/run -- "$A/boost.spec.luau"
check "AC2: in a session Boost is a per-player intent, one a tick and in the limit; it starts in play with a Boosted event and the frame's boosted, covers the factor's distance for TICKS steps, is dropped outside play, cools down, ends at a death; a hop and a pellet in a boost behave" lune run tests/run -- "$A/session.spec.luau"
check "AC3: Controls folds W and a swipe up through Boost.tap and sends Boost.INTENT; Main shows Boost.status on the HUD and the camera widens by Boost.fov" lune run tests/run -- "$A/place.spec.luau"
check "AC4: game-design.md states the boost and architecture.md declares Session -> Boost (place.spec's documents case)" lune run tests/run -- "$A/place.spec.luau"
check "AC5: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau

finish
