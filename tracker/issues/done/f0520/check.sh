#!/usr/bin/env bash
# Acceptance checks for f0520. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0520 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0520"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: the game runs at half speed: 15 steps per real second, 3.75 tiles/s, turn buffer 1.6 s" lune run tests/run -- "$A/speed.spec.luau"
check "AC2: the server clock and the client interpolation both use Session.STEP_RATE" lune run tests/run -- "$A/adapters.spec.luau"
check "AC3: game-design.md records the half speed" lune run tests/run -- "$A/docs.spec.luau"

finish
