#!/usr/bin/env bash
# Acceptance checks for f0310. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0310 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0310"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: every snapshot and frame carries the four ghosts (position, heading, look, flash, jumpTick) in a fixed order, and a session without ghosts is replicated exactly as before" lune run tests/run -- "$A/frame.spec.luau"
check "AC2: View.interpolateGhosts blends by elapsed time, never across a jump, and takes look and heading from the latest snapshot" lune run tests/run -- "$A/interpolate.spec.luau"
check "AC3: the ghost view is a thin client module that blends only through View.interpolateGhosts and is started and fed by the client entry point" lune run tests/run -- "$A/adapters.spec.luau"
existing_ac4_pass() { # the runner takes files, not directories
  local files
  files=$(find tests/acceptance/f0130 tests/acceptance/f0520 tests/acceptance/c0390 tests/unit/View tests/place -name '*.spec.luau' | sort)
  # shellcheck disable=SC2086
  lune run tests/run -- $files
}
check "AC4: every existing client, view and place spec still passes" existing_ac4_pass
check "AC5: the architecture rules hold (Logic is pure, every require declared in tracker/architecture.md, every feature has unit specs)" lune run tests/run -- tests/meta/architecture.spec.luau

finish
