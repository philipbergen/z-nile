#!/usr/bin/env bash
# Acceptance checks for f0065. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0065 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0065"

check "AC1: game over shows the results and the way back; a tap asks only when idle and set up" lune run tests/run -- "$A/results.spec.luau"
check "AC2: Session.isOver is true exactly at game over, per player" lune run tests/run -- "$A/over.spec.luau"
check "AC3: Returns teleports to the lobby only once Sessions says the run is over, with Travel's rules" lune run tests/run -- "$A/returns.spec.luau" "$A/sessions.spec.luau"
check "AC4: the game place's remotes, attribute and wiring, and FlowView on the fake client" lune run tests/run -- "$A/place.spec.luau" "$A/client.spec.luau"
check "AC5: from game over back to the lobby, end to end" lune run tests/run -- "$A/run.spec.luau"
check "AC6: Flow -> Travel is declared and Logic stays pure" lune run tests/run -- tests/meta/architecture.spec.luau

finish
