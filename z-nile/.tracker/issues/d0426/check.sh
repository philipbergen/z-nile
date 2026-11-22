#!/usr/bin/env bash
# Acceptance checks for d0426. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0426 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0426"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"
# Step 2 (the gate queue): the specs are z-nile's own, under its home's tests/tooling/ (this check.sh runs from there).
check "AC1: a second gate waits, names the holder, and proceeds however the first ends (exit, SIGKILL)" lune run tests/run -- tests/tooling/gatequeue.spec.luau
check "AC2: the wait is bounded; not started is exit 75, which the watch net reads as not run" lune run tests/run -- tests/tooling/gatequeue.spec.luau tests/tooling/gatequeue-net.spec.luau
check "AC3: ZN_GATE_QUEUE=off skips and says so; a stale description is never believed" lune run tests/run -- tests/tooling/gatequeue.spec.luau
check "AC4: the default folder is per user outside every checkout; --plan and inner runs take no lock; tests/run queues" lune run tests/run -- tests/tooling/gatequeue.spec.luau

finish
