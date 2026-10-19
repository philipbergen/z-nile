#!/usr/bin/env bash
# Acceptance checks for f0025. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0025 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0025"

check "AC1: one submission per run, from the server GameOver, and a new run may submit again" lune run tests/run -- "$A/run.spec.luau"
check "AC2: a disconnected player is kept through the dying pause, then dropped" lune run tests/run -- "$A/leave.spec.luau"
check "AC3: Sessions wires GameOver through that policy and keeps the pinned adapter shape" lune run tests/run -- "$A/sessions.spec.luau"

finish
