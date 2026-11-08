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
check "AC1: z-ticket's existing steps keep their numbers, labels and pinned sentences; its new steps (0a ask verbatim and dated, 0b interview with every question and answer in order, 2a the record, 3a the clean idea, 4a the idea review, 4b the user's confirmation) run in order; a dispatched capture does not stop and records unattended." lune run tests/run -- "$A/skills-ticket.spec.luau"
check "AC2: the capture record's sections, dated verbatim messages in fences, interview and idea are judged by capturecheck, and the skill's own template passes it." lune run tests/run -- "$A/shape.spec.luau"
check "AC3: ./zn audit reports a malformed record and a designed issue whose last confirmation is Unconfirmed, and checks none where there is no capture section." lune run tests/run -- "$A/audit.spec.luau"
check "AC4: every finding of an idea review is answered, the confirmation names the last round, and the unattended and user forms cannot be mixed; the Ask only grows." lune run tests/run -- "$A/review-record.spec.luau"
check "AC5: ./zn dispatch zz-review <id> --mode idea runs the model of the z-ticket-review activity and lands capture/idea-review-NNN.md with a capture-phase row." lune run tests/run -- "$A/dispatch.spec.luau"
check "AC6: ./zn land carries only the raw idea reviews of an unclaimed draft, and an Ask that only grows." lune run tests/run -- "$A/land.spec.luau"
check "AC7: zz-review has the idea mode: three sections seen, dropped, added and bent attacked." lune run tests/run -- "$A/skills-review.spec.luau"
check "AC8: z-design (confirms an unattended capture first), zz-rules and the README restate the flow." lune run tests/run -- "$A/skills-restated.spec.luau"
check "AC9: an agent-filed ticket is exempt only through the marker section; a ticket with a user ask cannot claim it; z-ticket says what an agent filing a ticket writes; --filed-by accepts a lesson, review finding or agent: finding only." lune run tests/run -- "$A/exempt.spec.luau"

check "AC10: an issue made after the capture record landed (it carries capture: required, written by ./zn new) is refused at the claim (status, and new raft for each member) and at design: reviewed|ready by the audit unless it has the record or the marker; only the frontmatter counts; no history is read, so a shallow clone judges it the same; an unmarked (older) issue is claimed as before." bash -c 'lune run tests/run -- "$0/cut.spec.luau" "$0/claim.spec.luau"' "$A"
check "AC11: ./zn new issue … --filed-by <source> writes the marker, the source and the Scope decision line and that ticket is claimed; it refuses an empty, free-text or user source and creates nothing; every skill's lesson line passes the flag." bash -c 'lune run tests/run -- "$0/claim.spec.luau" "$0/exempt.spec.luau"' "$A"

finish
