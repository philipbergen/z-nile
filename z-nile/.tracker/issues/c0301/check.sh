#!/usr/bin/env bash
# Acceptance checks for c0301. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0301 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0301"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: an empty Judged or Observed subsection (\"None.\") derives no claim, and every other claim keeps its number" \
  lune run tests/run -- "$A/claims.spec.luau"
check "AC2: a tests-only ticket's code cells cite a spec file the stack changed that its layer changed or its Touched modules name; a source citation, or a spec citation by any other ticket, fails naming the row" \
  lune run tests/run -- "$A/code.spec.luau"
check "AC3: ./zn trace prints no None. row, --check passes a source ticket stacked with a tests-only ticket only when each code cell cites its own ticket's files, and seal.trace's table for it passes" \
  lune run tests/run -- "$A/land.spec.luau"
check "AC4: zz-rules, zz-review and the trace contract state the new rules, and raftplan.touchedModules is the one Touched modules reader" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC5: the existing trace, stub-capture and raft-plan specs still pass" \
  lune run tests/run -- tests/tooling/trace.spec.luau tests/acceptance/c0330/stub.spec.luau \
  tests/acceptance/c0116/plan.spec.luau

finish
