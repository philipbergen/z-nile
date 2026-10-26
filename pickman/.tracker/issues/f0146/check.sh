#!/usr/bin/env bash
# Acceptance checks for f0146. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0146 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0146"

check "AC1: Pad's map, its left-stick fold (heading-relative sectors, hysteresis, one intent a push) and which input types are gamepads" lune run tests/run -- "$A/pad.spec.luau"
check "AC2: Pad.look's dead zone, squared response, directions and dt scaling, in View.look's units (pad.spec's look case)" lune run tests/run -- "$A/pad.spec.luau"
check "AC3: Controls, run on a stub, jumps on ButtonA and passes it on, sinking the rest; Sticks, run on a stub, folds the most recent controller's left stick; Camera looks with the right stick; the pad's continue asks only while the overlay asks" bash -c 'lune run tests/run -- "$1/place.spec.luau" "$1/flow.spec.luau" "$1/controls.spec.luau"' _ "$A"
check "AC4: the lobby's Main boots LobbyPad, which selects START GAME when a controller is the last input (place.spec's lobby case)" lune run tests/run -- "$A/place.spec.luau"
check "AC5: game-design.md's Platforms row includes gamepad and states the map; architecture.md declares Pad (place.spec's documents case)" lune run tests/run -- "$A/place.spec.luau"
check "AC6: Logic stays engine-free, every dependency is declared, and every feature has unit specs" lune run tests/run -- tests/meta/architecture.spec.luau

finish
