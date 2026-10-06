#!/usr/bin/env bash
# Acceptance checks for c0082. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0082 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0082"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: audit.run reports every problem of every kind in one run, at the right level, sorted" \
  lune run tests/run -- "$A/audit.spec.luau"
check "AC2: tracker.sh audit, list on a duplicate, renumber <directory>, and the skill text" \
  lune run tests/run -- "$A/cli.spec.luau"
check "AC3: the real tracker tree has no audit errors" \
  lune run tests/run -- "$A/real-tree.spec.luau"

finish
