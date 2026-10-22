#!/usr/bin/env bash
# Acceptance checks for f0100. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0100 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0100"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: the Blaster: seeded drops, at most three, spending, the fire intents, the shot's line and target" lune run tests/run -- "$A/blaster.spec.luau"
check "AC2: a fire shares the intent limit and is taken before anyone moves: one spent, the first active ghost eaten on the chain" lune run tests/run -- "$A/shots.spec.luau"
check "AC3: contact eats roll seeded drops, shot ghosts do not, at most three, shots outlive deaths and levels, every frame has the count" lune run tests/run -- "$A/drops.spec.luau"
check "AC4: the shot bars after the lives and the beam's end" lune run tests/run -- "$A/hud.spec.luau"
check "AC5: no new remote, the server adapter unchanged, Main feeds the HUD and the beam" lune run tests/run -- "$A/place.spec.luau"
check "AC6: Blaster is a declared, pure, unit-tested feature" lune run tests/run -- tests/meta/architecture.spec.luau

finish
