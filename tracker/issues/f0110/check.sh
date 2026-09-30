#!/usr/bin/env bash
# Acceptance checks for f0110. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0110 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0110"

check "AC1: straight movement, half-tile entry and wall stops" lune run tests/run -- "$A/straight.spec.luau"
check "AC2: classic corners: stop unless a matching turn is buffered" lune run tests/run -- "$A/corners.spec.luau"
check "AC3: buffered turns: first matching centre, latest wins, Forward clears, window" lune run tests/run -- "$A/buffer.spec.luau"
check "AC4: a stopped player turns at once when the exit exists" lune run tests/run -- "$A/stopped.spec.luau"
check "AC5: Back reverses immediately and clears the buffer" lune run tests/run -- "$A/back.spec.luau"
check "AC6: the door stops the player; tunnels wrap with Wrapped events" lune run tests/run -- "$A/tunnels.spec.luau"
check "AC7: invariants and determinism under random play on the classic maze" lune run tests/run -- "$A/invariants.spec.luau"
check "AC8: spawn, default config and config validation" lune run tests/run -- "$A/config.spec.luau"
check "AC9: late turns: one-tick cornering grace, missed turns discarded, otherwise buffered" lune run tests/run -- "$A/grace.spec.luau"

finish
