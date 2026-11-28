#!/usr/bin/env bash
# Acceptance checks for c0458. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0458 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0458"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: caps are idea 1 and 1/2/3, only design/raft/final review, code-review and code-answer are gone, final-review is light/heavy/ultra by level" lune run tests/run -- "$A/caps-modes.spec.luau"
check "AC2: every built raft goes to the final review, an easy ticket off the light path is not drafted and ready accepts it" lune run tests/run -- "$A/walk.spec.luau"
check "AC3: the skills say it: Code checks kept under Code mode, no Stream mode, design review only for risky, no removed modes" lune run tests/run -- "$A/docs.spec.luau"
check "AC4: the publisher's raise exception covers the stop of a raft of several tickets and refuses everything else" lune run tests/run -- "$A/publish.spec.luau"

finish
