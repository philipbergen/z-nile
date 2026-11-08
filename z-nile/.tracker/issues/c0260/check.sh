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
check "AC1: z-ticket's steps run ask, interview, classify, create, clean idea, review, confirm, land; it keeps every question and answer, and a dispatched capture stops for no one" lune run tests/run -- "$A/skills-ticket.spec.luau"
check "AC2: the capture folder's ask.md shape (sections, interview, verbatim ask) is judged by capturecheck, and the skill's own template passes it" lune run tests/run -- "$A/shape.spec.luau"
check "AC3: ./zn audit reports a malformed capture folder and checks none where there is no capture/" lune run tests/run -- "$A/audit.spec.luau"
check "AC4: every finding of an idea review is answered, and the confirmation names the last review round" lune run tests/run -- "$A/review-record.spec.luau"
check "AC5: ./zn dispatch zz-review --mode idea lands capture/idea-review-NNN.md and records a capture-phase row" lune run tests/run -- "$A/dispatch.spec.luau"
check "AC6: ./zn land accepts exactly the capture files of a draft issue" lune run tests/run -- "$A/land.spec.luau"
check "AC7: zz-review has the idea mode with its seven attacks" lune run tests/run -- "$A/skills-review.spec.luau"
check "AC8: z-design, zz-rules and the README restate the new flow" lune run tests/run -- "$A/skills-restated.spec.luau"

finish
