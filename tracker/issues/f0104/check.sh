#!/usr/bin/env bash
# Acceptance checks for f0104. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0104 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0104"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: exactly ten keys: W A S D move, Space jumps, E fires, the arrows look" lune run tests/run -- "$A/keys.spec.luau"
check "AC2: the arrow look turns at the turn rate, springs back, and gives way to the mouse" lune run tests/run -- "$A/look.spec.luau"
check "AC3: the aim is the nearest heading to the arrows or the look, ties the way of travel" lune run tests/run -- "$A/aim.spec.luau"
check "AC4: Controls and Camera relay the keys, the look, the hop and the aimed shot" lune run tests/run -- "$A/place.spec.luau"
check "AC5: end to end, a dropped shot fired with E down the corridor an arrow looks along eats the ghost there" lune run tests/run -- "$A/hunt.spec.luau"
check "AC6: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau

finish
