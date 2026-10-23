#!/usr/bin/env bash
# Acceptance checks for f0014. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0014 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0014"

check "AC1: View.walls: merged runs, periodic margins on wrapping axes" lune run tests/run -- "$A/walls.spec.luau"
check "AC2: world scale and heading yaw conventions" lune run tests/run -- "$A/pose.spec.luau"
check "AC3: snapshot interpolation, without sliding across a tunnel jump" lune run tests/run -- "$A/interpolate.spec.luau"
check "AC4: yaw smoothing and free look" lune run tests/run -- "$A/look.spec.luau"
check "AC5: key map" lune run tests/run -- "$A/keys.spec.luau"
check "AC6: the client Main boots MazeView, Camera and Controls, which use View" lune run tests/run -- "$A/place.spec.luau"

finish
