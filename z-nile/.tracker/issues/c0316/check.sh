#!/usr/bin/env bash
# Acceptance checks for c0316. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0316 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0316"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the documents carry the statement, its pointers and the first lesson" lune run tests/run -- "$A/docs.spec.luau"
check "AC2: harvest.md takes an escape entry, a finding names its stage, and --check refuses an entry with nothing behind it" lune run tests/run -- "$A/escapes.spec.luau"
check "AC3: --uncovered lists every redesign, stop and rework with no entry, and prints what it printed before without them" lune run tests/run -- "$A/escapes.spec.luau"
check "AC4: a finding with no valid Stage line is named, except in a review from before the rule" lune run tests/run -- "$A/escapes.spec.luau"
check "AC5: status prepared and done refuse work with an unharvested finding, an escape with no entry or an unmarked finding" lune run tests/run -- "$A/gates.spec.luau"
check "AC6: stop counts a started raft's stop, ready and work next refuse it until its entry exists, and a capture can name what it reworks" lune run tests/run -- "$A/gates.spec.luau"
check "AC7: metrics prints escapes by the stage that made and the stage that found them, before the Rework lines" lune run tests/run -- "$A/escapes.spec.luau" "$A/report.spec.luau"
ac8() {
  lune run tests/run -- tests/acceptance/c0111/harvest.spec.luau tests/acceptance/c0111/lesson-format.spec.luau tests/acceptance/c0111/lessons-cli.spec.luau tests/acceptance/c0111/metrics-lessons.spec.luau tests/acceptance/c0111/skill-docs.spec.luau tests/acceptance/c0115/readme.spec.luau tests/acceptance/c0115/docs.spec.luau tests/acceptance/c0259/readme.spec.luau tests/acceptance/c0119/scope-docs.spec.luau tests/acceptance/c0191/docs.spec.luau tests/acceptance/c0043/rounds.spec.luau tests/acceptance/c0084/metrics-phases.spec.luau || return 1
  (cd "$(git rev-parse --show-toplevel)" && ./zn lessons --check)
}
check "AC8: the promoted lessons, docs and metrics specs pass, and lessons --check passes on the real tree" ac8

finish
