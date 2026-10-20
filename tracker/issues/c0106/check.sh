#!/usr/bin/env bash
# Acceptance checks for c0106. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0106 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0106"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: radar.spec accepts today's and f0029's layout, rejects a changed or missing number, changes nothing else" lune run tests/run -- "$A/narrow-radar.spec.luau"
check "AC2: adapter.spec accepts the three- and the five-argument radarBox line, rejects the regressions, changes nothing else" lune run tests/run -- "$A/narrow-adapter.spec.luau"
check "AC3: the two narrowed d0105 specs pass on the current tree" lune run tests/run -- tests/acceptance/d0105/radar.spec.luau tests/acceptance/d0105/adapter.spec.luau

finish
