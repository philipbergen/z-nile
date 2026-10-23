#!/usr/bin/env bash
# Acceptance checks for c0129. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0129 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0129"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: Submits has no play-again hook: exports ready, step, pending, close; no onAgain; no again hook in src/server" lune run tests/run -- "$A/submits.spec.luau"
check "AC2: Hiscores.onAgain stays and an accepted play again is the next run" lune run tests/run -- "$A/onagain.spec.luau"
check "AC3: the full gate passes" z-nile/check.sh --full

finish
