#!/usr/bin/env bash
# Acceptance checks for f0143. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0143 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0143"

check "AC1: Boost's constants, start, span, cooldown, capped and rounded speed, status at a frame, double tap and FOV ramp as shown; the HUD chevron's box after the shot bars; on every level a boost gains two tiles on a hunting ghost within a tile a step" lune run tests/run -- "$A/boost.spec.luau"
check "AC2: in a session Boost is a per-player intent, one a tick and in the limit, and cancels a buffered turn as W does; it starts in play with a Boosted event and the frame's boosted, covers the factor's distance for TICKS steps, stacks on the frightened speed, is dropped outside play, cools down, ends at a death, a new level and a new run; a hop and a pellet in a boost behave" lune run tests/run -- "$A/session.spec.luau"
check "AC3: Controls and Sticks, run on a stub with a scripted clock, send Boost on the press after a double tap of W, of the D-pad's Up, of a swipe up or of the left stick pushed up (one Taps for keys, one for touch, one for the stick), and never for a slow pair, a release or other intents; HudView, run on a stub, places the chevron after the shot bars in the safe area and colours it; Main shows Boost.status on the HUD and the camera widens by Boost.fov at the shown tick" bash -c 'lune run tests/run -- "$1/controls.spec.luau" "$1/hud.spec.luau" "$1/place.spec.luau"' _ "$A"
check "AC4: game-design.md states the boost and architecture.md declares Session -> Boost (place.spec's documents case)" lune run tests/run -- "$A/place.spec.luau"
check "AC5: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau
check "AC6: on a controller the left stick's click (Pad.BUTTONS.ButtonL3 = \"Boost\") sends Boost alone on the press, and a quick double push of the left stick up boosts (controls.spec's L3 and stick cases)" lune run tests/run -- "$A/controls.spec.luau"
check "AC7: f0126's pick stop caps the step after the boost: a boosted player asking for a pick stops on the centre beside the marked wall and the pick starts" lune run tests/run -- "$A/pick.spec.luau"

finish
