#!/usr/bin/env bash
# Acceptance checks for c0119. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0119 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0119"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: the skills carry the scope rules where the Design puts them" lune run tests/run -- "$A/scope-docs.spec.luau"
check "AC2: the two scope lessons are valid and sourced from the R0042 correction" lune run tests/run -- "$A/scope-lessons.spec.luau"
check "AC3: the real tree's lessons and ledgers are valid" scripts/tracker.sh lessons --check
check "AC4: tracker.sh capture prints an item's capture across moves and legacy names, and marks what it does not follow" lune run tests/run -- "$A/capture-cli.spec.luau"

finish
