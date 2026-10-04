#!/usr/bin/env bash
# Acceptance checks for c0450. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0450 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0450"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: ticket-prep step 3 has the Override check, before Test plan" lune run tests/run -- "$A/override-check.spec.luau"
check "AC2: design-mode review rates an unnamed override high" lune run tests/run -- "$A/override-check.spec.luau"
check "AC3: the issue template has a visible Overrides line outside its comment" lune run tests/run -- "$A/override-check.spec.luau"
check "AC4: ready-raft's readiness step stops on an unfinished depends_on" lune run tests/run -- "$A/override-check.spec.luau"
check "AC5: the acceptance spec is formatted and linted" bash -c 'stylua --check "$0" && selene --quiet "$0"' "$A"
check "AC6: the full gate passes" scripts/check.sh --full

finish
