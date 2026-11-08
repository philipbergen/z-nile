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
check "AC1: the actor grammar, one model-id spelling, the live inputs and the resolution order (flag, env, agent session, git name) hold" \
  lune run tests/run -- "$A/provenance.spec.luau"
check "AC2: a Co-Authored-By trailer becomes a normalised agent actor, and a trailer whose email is a commit author's is a person" \
  lune run tests/run -- "$A/provenance.spec.luau"
check "AC3: ./zn who prints the idea's author from the capture commit and each status change's author from git, for old items too, and writes nothing" \
  lune run tests/run -- "$A/who.spec.luau" "$A/provenance.spec.luau"
check "AC4: ./zn approve records the human, the design hash and the user's words as the human's commit, and refuses a worker, the main checkout, an undesigned issue and an agent without the user's words" \
  lune run tests/run -- "$A/approve.spec.luau"
check "AC5: status prepared is refused until the newest approval matches the design, a redesign makes it stale, and a raft's move needs each issue it moves approved" \
  lune run tests/run -- "$A/approve.spec.luau" "$A/provenance.spec.luau"
check "AC6: unblocked, rafted and delivered rows are appended per ticket by the commands that make the events, ./zn record takes the other tickets' events, and the publish, rafting and capture guards let only appended rows through" \
  lune run tests/run -- "$A/record.spec.luau" "$A/lifecycle.spec.luau" "$A/dispatch.spec.luau" "$A/publish.spec.luau" "$A/provenance.spec.luau"
check "AC7: the dispatcher never passes the prep gate, a worker cannot approve, and each attempt of a step has ZN_ACTOR from its own spec" \
  lune run tests/run -- "$A/dispatch.spec.luau"
check "AC8: who merges the derived entries and the record, oldest first, the record winning over a git fallback, with one pure per-item commit selector" \
  lune run tests/run -- "$A/who.spec.luau" "$A/provenance.spec.luau"
check "AC9: the board page lists an item's provenance in its view" \
  lune run tests/run -- "$A/who.spec.luau"
check "AC10: ./zn audit refuses a malformed record, an unknown event, a bad actor and a record in a raft's folder, and accepts absence" \
  lune run tests/run -- "$A/record.spec.luau" "$A/provenance.spec.luau"
check "AC11: zz-rules, z-design, z-raft, zz-execute and the README document approve, who, record, the actor options and the session variables" \
  lune run tests/run -- "$A/provenance.spec.luau"
check "AC12: the real tree audits and lessons-checks clean and the promoted specs this issue does not override stay green" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- tests/acceptance/c0072/land.spec.luau tests/acceptance/c0073/board-stats.spec.luau tests/acceptance/c0081/publish-guard.spec.luau tests/acceptance/c0053/publish.spec.luau tests/acceptance/c0116/plan.spec.luau'

finish
