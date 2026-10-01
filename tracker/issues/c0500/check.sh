#!/usr/bin/env bash
# Acceptance checks for c0500. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0500 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0500"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: renumber without <new> picks one above the highest number across the local tree and origin/main, refuses when that is unknown or full, and still honors an explicit <new>" lune run tests/run -- "$A/renumber.spec.luau"
check "AC2: tracker.sh new keeps its multiple-of-10 spacing" lune run tests/run -- "$A/new-spacing.spec.luau"
check "AC3: the tracker skill's Conflicts bullet describes the new renumber" lune run tests/run -- "$A/skill-doc.spec.luau"

finish
