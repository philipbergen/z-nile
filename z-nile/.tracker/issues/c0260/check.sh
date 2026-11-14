#!/usr/bin/env bash
# Acceptance checks for c0260. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0260 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0260"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: z-ticket's existing steps keep their numbers, labels and pinned sentences; its new sub-steps (0a ask verbatim and dated, 0b interview with every question and answer in order, 2a keep the record, 4a show the idea and its challenge, 4b the user's confirmation) run in order; a dispatched capture does not stop and records unattended." lune run tests/run -- "$A/skills-ticket.spec.luau"
check "AC2: the capture record's three sections (dated verbatim messages in fences, numbered interview, confirmation) are judged by capturecheck; ./zn idea --record appends only, and the skill's own template is accepted." lune run tests/run -- "$A/shape.spec.luau"
check "AC3: ./zn audit reports a malformed record, a confirmation of another round than the last review, and a designed issue whose last confirmation is Unconfirmed, and checks none where there is no capture section." lune run tests/run -- "$A/audit.spec.luau"
check "AC4: ./zn idea --record keeps messages and questions in order and starts no model; --confirm writes the user's words after the last round and is refused while a point is unruled or by a dispatched run; a change is the next round and drops the Confirmed line; a dispatched capture records Unconfirmed (unattended)." lune run tests/run -- "$A/record.spec.luau"
check "AC5: the author and the challenger of ./zn idea are given the user's own Ask and Interview, and the challenger is told to check the idea against them (dropped, added, bent)." lune run tests/run -- "$A/record.spec.luau"
check "AC6: ./zn land carries the idea: line, the idea reviews and refutes of an unclaimed draft, and an Ask and Interview that only grow; it refuses everything else beside the document, a Confirmed line from a dispatched run and any change to the agent marker." lune run tests/run -- "$A/land.spec.luau"
check "AC7: zz-review's idea challenge judges the idea against the Ask and the Interview: dropped, added and bent." lune run tests/run -- "$A/skills-restated.spec.luau"
check "AC8: z-design (confirms an unattended capture first), zz-review, zz-rules and the README restate the flow." lune run tests/run -- "$A/skills-restated.spec.luau"
check "AC9: an agent-filed ticket is exempt only through the marker section; a ticket with a user ask cannot claim it; --filed-by accepts a lesson, review finding or agent: finding only, and writes no idea: key; z-ticket says what an agent filing a ticket writes; every skill's lesson line passes the flag." lune run tests/run -- "$A/exempt.spec.luau"

check "AC10: an issue made after the capture record landed (it carries capture: required, written by ./zn new) is refused at the claim (status, and new raft for each member) and at design: reviewed|ready by the audit unless it has the record or the marker; only the frontmatter counts; no history is read, so a shallow clone judges it the same; an unmarked (older) issue is claimed as before." bash -c 'lune run tests/run -- "$0/cut.spec.luau" "$0/claim.spec.luau"' "$A"
check "AC11: ./zn new issue … --filed-by <source> writes the marker, the source and the Scope decision line and that ticket is claimed; it refuses an empty, free-text or user source and creates nothing." bash -c 'lune run tests/run -- "$0/claim.spec.luau" "$0/exempt.spec.luau"' "$A"

finish
