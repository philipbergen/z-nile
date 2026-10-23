#!/usr/bin/env bash
# Acceptance checks for c0107. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0107 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0107"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: each raft and issue is in one readiness group with its next command" lune run tests/run -- "$A/views.spec.luau"
check "AC2: a raft's shown type comes from its issues, and the colors stay distinct" lune run tests/run -- "$A/label.spec.luau"
check "AC3: Rafts and Issues replace the old tabs, and the copy button writes the command" lune run tests/run -- "$A/page.spec.luau"
check "AC4: search, dependencies and Stats stay, and the skill describes the new board" lune run tests/run -- "$A/keep.spec.luau"

finish
