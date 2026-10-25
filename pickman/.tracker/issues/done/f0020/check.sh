#!/usr/bin/env bash
# Acceptance checks for f0020. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0020 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0020"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: each ghost scatters to its own corner and chases as its personality says (Blinky, Pinky, Inky, Clyde), and the classic no-up junctions are the documented four" lune run tests/run -- "$A/targets.spec.luau"
check "AC2: a ghost takes the exit closest to its target in a straight line, ties up-left-down-right, never turns back unless dead end, never up on a no-up junction, never into the door or house unless told" lune run tests/run -- "$A/exits.spec.luau"
check "AC3: walking is whole units along the rails with one decision per centre, wraps through tunnels, never leaves legal tiles, never turns back by itself, and is deterministic" lune run tests/run -- "$A/walking.spec.luau"
check "AC4: the architecture rules hold (Logic is pure, every require declared in tracker/architecture.md, every feature has unit specs)" lune run tests/run -- tests/meta/architecture.spec.luau

finish
