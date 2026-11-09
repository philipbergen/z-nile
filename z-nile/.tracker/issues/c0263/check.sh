#!/usr/bin/env bash
# Acceptance checks for c0263. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0263 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0263"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the actor grammar, one model-id spelling, the agent-session hint and the resolution order (flag, env, agent session, git name) hold, and ./zn record records the actor from each source" \
  lune run tests/run -- "$A/provenance.spec.luau" "$A/record.spec.luau"
check "AC2: provenance.md rows are unnumbered, in a closed event list, parsed strictly, appended only, and two writers' rows are united base, main, ours" \
  lune run tests/run -- "$A/provenance.spec.luau"
check "AC3: ./zn record publishes unblocked, confirmed and ranked rows from origin/main's file on a backlog item, a raft and (unblocked only) an active item, and refuses the rest" \
  lune run tests/run -- "$A/record.spec.luau"
check "AC4: the publish validator lets a provenance.md through only as a create or an append of published events, and refuses everything else naming the file" \
  lune run tests/run -- "$A/publish.spec.luau"
check "AC5: ./zn audit refuses a malformed record, an unknown event, a bad actor and a header naming another id, accepts absence and a raft's record" \
  lune run tests/run -- "$A/record.spec.luau" "$A/provenance.spec.luau"
check "AC6: the engine's merges of origin/main (sync, fold, land) unite a conflict confined to records (found by the item, whichever side moved its folder), abort on any other, and a record added where the other side moved the folder follows the folder" \
  lune run tests/run -- "$A/record.spec.luau"
check "AC7: zz-rules and the README document provenance.md, ./zn record, the actor options, the session variables and the union through ./zn sync" \
  lune run tests/run -- "$A/provenance.spec.luau"
check "AC8: the real tree audits and lessons-checks clean and the promoted specs this layer does not override stay green" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- tests/acceptance/c0072/land.spec.luau tests/acceptance/c0081/publish-guard.spec.luau tests/acceptance/c0053/publish.spec.luau tests/acceptance/c0084/spend-command.spec.luau'

finish
