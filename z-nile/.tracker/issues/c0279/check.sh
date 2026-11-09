#!/usr/bin/env bash
# Acceptance checks for c0279. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0279 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0279"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the stop case and the fakes it runs wait for nothing on the wall clock" lune run tests/run -- "$A/no-wall-clock.spec.luau"
# a slow machine, simulated: the fakes wait 3 s (over stall_seconds = 2 and over the old 3 s wait for the grandchild)
# before the stop and before the push, and every case of the dispatch spec still passes
check "AC2: with the fakes delayed 3 s the whole dispatch spec passes" env FAKE_DELAY=3 lune run tests/run -- tests/acceptance/c0117/dispatch-cli.spec.luau

finish
