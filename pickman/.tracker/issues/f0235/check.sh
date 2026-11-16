#!/usr/bin/env bash
# Acceptance checks for f0235. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0235 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0235"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a power pellet's beacon is a pillar on its tile from the pellet to BEACON.top, 8 studs over the walls, 4 over the ghosts, past a jump's top eye, and seen across the classic maze from a jump's top" lune run tests/run -- "$A/beacon.spec.luau"
check "AC2: beacons show exactly while the drawn eye is above the wall tops (a hop's and a long hop's airborne span, a held jump top), only for power pellets still present, and none within BEACON.clear tiles of the eye" lune run tests/run -- "$A/rule.spec.luau"
check "AC3: PelletView builds a hidden neon Beacon per power pellet at View.beacon and shows, each frame, those View.beacons says for the getters' eye and place, writing only beacons whose state changed; beacons never pulse; the pellets and their pulse unchanged" lune run tests/run -- "$A/pellets.spec.luau"
check "AC4: Camera.eye is the height the real Camera built its CFrame at on every frame (nil before a snapshot); Main starts PelletView with Camera.eye and Camera.pose; PelletView calls them, reads no camera, keeps no hop and sends nothing" lune run tests/run -- "$A/camera.spec.luau" "$A/place.spec.luau"
check "AC5: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau
check "AC6: game-design.md has one (prep) Power pellet beacons bullet for f0235 after the glows, with its purpose, numbers, when it shows, its clearance and how it follows the pellets; architecture.md's View row names the beacons" lune run tests/run -- "$A/docs.spec.luau"

finish
