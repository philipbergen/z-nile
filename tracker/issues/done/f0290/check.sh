#!/usr/bin/env bash
# Acceptance checks for f0290. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0290 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0290"

check "AC1: the pellets' wire format: slots, a 41-character code for the classic maze, strict decode" lune run tests/run -- "$A/wire.spec.luau"
check "AC2: every frame carries the player's pellets: eaten ones gone, all back on a new level or run, kept on death" lune run tests/run -- "$A/frame.spec.luau"
check "AC3: View places pellets at tile centres below the eye, power pellets bigger and pulsing, visible down the longest corridor" lune run tests/run -- "$A/placement.spec.luau"
check "AC4: the client draws pellets through a thin PelletView fed each frame's pellets" lune run tests/run -- "$A/place.spec.luau"
check "AC5: View uses Pellets through a declared, acyclic edge, and Logic stays pure" \
  bash -c 'grep -qF "require(\"./Pellets\")" src/shared/Logic/View/init.luau && lune run tests/run -- tests/meta/architecture.spec.luau'

finish
