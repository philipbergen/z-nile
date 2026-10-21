#!/usr/bin/env bash
# Acceptance checks for f0033. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0033 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0033"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: the radar and the edge indicators are computed as specified: bearing, border point, path distance, field of view, nearest first, strictly growing and brightening as a ghost nears" lune run tests/run -- "$A/awareness.spec.luau"
check "AC2: the danger HUD is a thin client module that draws only what Awareness returns, and the camera hands over its pose without a second interpolation" lune run tests/run -- "$A/adapters.spec.luau"
existing_ac3_pass() { # the runner takes files, not directories
  local files
  files=$(find tests/acceptance/f0014 tests/acceptance/f0054 tests/acceptance/c0041 tests/unit/View tests/place -name '*.spec.luau' | sort)
  # shellcheck disable=SC2086
  lune run tests/run -- $files
}
check "AC3: every existing client, view and place spec still passes" existing_ac3_pass
check "AC4: the architecture rules hold (Logic is pure, every require declared in tracker/architecture.md, every feature has unit specs)" lune run tests/run -- tests/meta/architecture.spec.luau

finish
