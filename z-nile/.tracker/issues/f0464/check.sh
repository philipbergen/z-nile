#!/usr/bin/env bash
# Acceptance checks for f0464. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0464 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0464"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the one decision readies any prepared raftless ticket alone, light only by light.luau, with its trailers" lune run tests/run -- "$A/single.spec.luau"
check "AC2: ready <issue> end to end: one claim commit, dispatched by the approval rule, --on on a finished raft" lune run tests/run -- "$A/ready.spec.luau"
check "AC3: work next answers ready <issue> (or --on <R>) for a prepared raftless ticket, never rafting" lune run tests/run -- "$A/walk.spec.luau"
check "AC4: the dispatcher readies a raftless ticket by z-ready on it, never raft-plan or z-raft" lune run tests/run -- "$A/dispatch.spec.luau"
check "AC5: raft-plan makes no raft by default, and a raft of several still needs its coherence review" lune run tests/run -- "$A/plan.spec.luau"
check "AC6: the skills and documents say a ticket is readied alone" lune run tests/run -- "$A/docs.spec.luau"
check "AC7: the publish guard takes a single raft with no light: line and refuses any light: but true" lune run tests/run -- "$A/guard.spec.luau"

finish
