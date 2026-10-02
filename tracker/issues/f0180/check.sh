#!/usr/bin/env bash
# Acceptance checks for f0180. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0180 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0180"

check "AC1: Hud.model shows the score, level, lives and the share of the level's power time left" lune run tests/run -- "$A/hud.spec.luau"
check "AC2: Hud.layout keeps the HUD readable on any screen: 14-40 px text, a band under 15% of the height" lune run tests/run -- "$A/layout.spec.luau"
check "AC3: the client draws the HUD through a thin HudView fed each frame's play record" lune run tests/run -- "$A/place.spec.luau"
check "AC4: Hud is a declared feature with unit specs, and Logic stays pure" \
  bash -c 'test -f src/shared/Logic/Hud/init.luau && ls tests/unit/Hud/*.spec.luau && lune run tests/run -- tests/meta/architecture.spec.luau'

finish
