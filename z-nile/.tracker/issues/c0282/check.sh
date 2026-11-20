#!/usr/bin/env bash
# Acceptance checks for c0282. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0282 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0282"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: status <id> new publishes an unblocked row for each issue it gives back in the same commit as the status line (never for a raft, none for release), built from origin/main's file, and a bad actor, a bad ZN_VIA or no git identity refuses before anything is published" \
  lune run tests/run -- "$A/record.spec.luau"
check "AC2: new raft (published and offline), fold, recombine and an emergent new issue --raft append a rafted row per ticket, with via= only under ZN_VIA, unfold keeps the history, and a bad actor refuses before the claim is published" \
  lune run tests/run -- "$A/record.spec.luau" "$A/lifecycle.spec.luau" "$A/provenance.spec.luau"
check "AC3: done appends a delivered row to every member (an old member with no record gets one), staged with the moves, none for the raft, none left by a failed done, one after the retry, no worker" \
  lune run tests/run -- "$A/lifecycle.spec.luau"
check "AC4: each attempt of a dispatched model step has ZN_ACTOR from its own spec (one spelling per model), and a script step records the user who started the pipeline with via=dispatch:<step>" \
  lune run tests/run -- "$A/dispatch.spec.luau" "$A/provenance.spec.luau"
check "AC5: the rafting gate merges a rafting PR whose backlog issues carry rafted rows appended to what main holds, and refuses any other event, an edited old row, a record of an issue that is not in the backlog, a raft's record and any other file" \
  lune run tests/run -- "$A/dispatch.spec.luau"
check "AC6: zz-rules documents the lifecycle rows, ZN_VIA and the rafting gate's allowance, and the README names the three events" \
  lune run tests/run -- "$A/provenance.spec.luau"
check "AC7: the real tree audits and lessons-checks clean and the promoted specs this layer touches stay green" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- tests/acceptance/c0053/commands-prep.spec.luau tests/acceptance/c0053/commands-claim.spec.luau tests/acceptance/c0084/spend-command.spec.luau tests/acceptance/c0074/done-gate.spec.luau tests/acceptance/c0116/recombine.spec.luau tests/acceptance/c0116/claims.spec.luau tests/acceptance/c0001/tracker-lifecycle.spec.luau tests/tooling/dispatch-guards.spec.luau'

finish
