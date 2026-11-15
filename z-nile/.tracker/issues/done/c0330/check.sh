#!/usr/bin/env bash
# Acceptance checks for c0330. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0330 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0330"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a template-only, empty or absent captured Solution yields no S claim and no refusal, and keeps its P and AC claims" lune run tests/run -- "$A/stub.spec.luau"
check "AC2: a captured Solution with outcomes still yields one S claim per outcome" lune run tests/run -- "$A/stub.spec.luau"
check "AC3: no Problem outcome, or no acceptance criteria, is still refused" lune run tests/run -- "$A/stub.spec.luau"
check "AC4: the skeleton has no S row for a stub ticket and the check expects none" lune run tests/run -- "$A/stub.spec.luau"
check "AC5: a readied ticket takes its claims from the captured text" lune run tests/run -- "$A/stub.spec.luau"
check "AC6: the zz-rules trace row and the engine contract state the stub rule" lune run tests/run -- "$A/stub.spec.luau"
check "AC7: trace.spec passes, its noSolution block asserting no refusal" bash -c 'grep -qF "c0330: an empty or template-only captured Solution" tests/tooling/trace.spec.luau && lune run tests/run -- tests/tooling/trace.spec.luau'
check "AC8: a section whose first read finds no outcome is read again with decision lines as text" lune run tests/run -- "$A/stub.spec.luau"
check "AC9: a Solution of text with no outcome is still refused" lune run tests/run -- "$A/stub.spec.luau"
check "AC10: trace-land with a stub-captured ticket lands" bash -c 'grep -qF "so no S claim" tests/tooling/trace-land.spec.luau && lune run tests/run -- tests/tooling/trace-land.spec.luau'

finish
