#!/usr/bin/env bash
# Acceptance checks for c0050. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0050 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0050"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: start refuses an issue whose dependency outside the raft is unknown, in the backlog or active, naming both ids" lune run tests/run -- "$A/start-depends.spec.luau"
check "AC2: a refused start changes nothing" lune run tests/run -- "$A/start-depends.spec.luau"
check "AC3: start proceeds once the dependency is done, and for a dependency on a raft-mate" lune run tests/run -- "$A/start-depends.spec.luau"
check "AC4: the tracker skill's start row documents the rule" lune run tests/run -- "$A/start-depends.spec.luau"
check "AC5: the acceptance spec is formatted and linted" bash -c 'stylua --check "$0" && selene --quiet "$0"' "$A"
check "AC6: the full gate passes" ./check.sh --full

finish
