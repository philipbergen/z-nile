#!/usr/bin/env bash
# Acceptance checks for f0210. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0210 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0210"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: Blinky starts outside and the others leave the house by the personal counters, the idle timer and the global counter after a death" lune run tests/run -- "$A/release.spec.luau"
check "AC2: a ghost leaves through the door, and an eaten ghost goes home as eyes through the door and comes out again, dangerous and without turning back, at twice the player's speed; blue-ness belongs to each ghost" lune run tests/run -- "$A/eyes.spec.luau"
check "AC3: the architecture rules hold (Logic is pure, every require declared in tracker/architecture.md, every feature has unit specs)" lune run tests/run -- tests/meta/architecture.spec.luau

finish
