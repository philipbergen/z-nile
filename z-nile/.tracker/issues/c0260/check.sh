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
check "AC1: z-ticket's steps run ask, interview, classify, create, clean idea, review, confirm, land; every message and every question and answer is kept; a dispatched capture records unattended and leaves the confirmation to z-design" lune run tests/run -- "$A/skills-ticket.spec.luau"
check "AC2: the capture record's sections (dated verbatim ask in fences, interview, idea) are judged by capturecheck, and the skill's own template passes it" lune run tests/run -- "$A/shape.spec.luau"
check "AC3: ./zn audit reports a malformed capture record and a designed issue still Unconfirmed, and checks none where there is no capture section" lune run tests/run -- "$A/audit.spec.luau"
check "AC4: every finding of an idea review is answered, the confirmation names the last round, and the unattended and user forms cannot be mixed" lune run tests/run -- "$A/review-record.spec.luau"
check "AC5: ./zn dispatch zz-review --mode idea runs the model of the z-ticket-review activity and lands capture/idea-review-NNN.md with a capture-phase row" lune run tests/run -- "$A/dispatch.spec.luau"
check "AC6: ./zn land accepts only the raw idea reviews of an unclaimed draft and an Ask that only grows" lune run tests/run -- "$A/land.spec.luau"
check "AC7: zz-review has the idea mode: three sections seen, dropped, added and bent attacked" lune run tests/run -- "$A/skills-review.spec.luau"
check "AC8: z-design, zz-rules and the README restate the new flow" lune run tests/run -- "$A/skills-restated.spec.luau"
check "AC9: an agent-filed ticket is exempt only through the marker section, and a ticket with a user ask cannot claim it" lune run tests/run -- "$A/exempt.spec.luau"

check "AC10: an issue made after the capture record landed is refused at the claim and at reviewed|ready unless it has the record or the marker; the cut-over is read from git's history, never from a date, and an unreadable history fails closed" bash -c 'lune run tests/run -- "$0/cut.spec.luau" "$0/claim.spec.luau"' "$A"
check "AC11: ./zn new issue --filed-by writes the exemption marker and refuses an empty, free-text or user source; every skill's lesson line passes it" bash -c 'lune run tests/run -- "$0/claim.spec.luau" "$0/exempt.spec.luau"' "$A"

finish
