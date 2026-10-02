#!/usr/bin/env bash
# Acceptance checks for f0670. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0670 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0670"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: Travel validates the destination and lets one request per player run at a time, times out an unanswered one and cools down after a failure" lune run tests/run -- "$A/travel.spec.luau"
check "AC2: Lobby gives the hiscore panel (the empty state, rank order, at most ten rows) and the start button for each status" lune run tests/run -- "$A/lobby.spec.luau"
check "AC3: the lobby as a player lives it: a press, a failed teleport, the wait, a second try and the teleport, two players, and no destination" lune run tests/run -- "$A/lobby-run.spec.luau"
check "AC4: the lobby place builds from lobby.project.json with its own remotes, an unset destination, its own scripts and the shared Logic and none of the game's adapters, and the game place is untouched" lune run tests/run -- "$A/lobby-place.spec.luau"
check "AC5: the real lobby adapters, run against a fake engine, stay thin and safe: the server never reads the client's payload, takes the destination from configuration, teleports once and only after Travel says go, and tells the player what Travel says; the client draws Lobby's models for every status and sends one argument-free request" lune run tests/run -- "$A/lobby-adapters.spec.luau"
check "AC6: the tooling knows both places: place.load builds either, a change to lobby.project.json selects the place specs, and the gate builds both" lune run tests/run -- "$A/lobby-tooling.spec.luau"
check "AC7: Travel and Lobby are declared features with unit specs, and Logic stays pure" \
  bash -c 'test -f src/shared/Logic/Travel/init.luau && test -f src/shared/Logic/Lobby/init.luau && ls tests/unit/Travel/*.spec.luau tests/unit/Lobby/*.spec.luau && lune run tests/run -- tests/meta/architecture.spec.luau'

finish
