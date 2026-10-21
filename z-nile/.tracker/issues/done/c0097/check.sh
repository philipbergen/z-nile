#!/usr/bin/env bash
# Acceptance checks for c0097. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0097 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0097"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
lock_case() { # the case exists and the whole spec passes
  grep -qF "it(\"ignores the runner's lock" tests/acceptance/c0049/spec-isolation.spec.luau || { echo "c0049 has no case for the runner's lock"; return 1; }
  lune run tests/run -- tests/acceptance/c0049/spec-isolation.spec.luau
}
check "AC1: c0049 passes, the runner's lock exempt by its own case" lock_case

finish
