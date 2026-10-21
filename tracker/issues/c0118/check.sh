#!/usr/bin/env bash
# Acceptance checks for c0118. SEQUESTERED: never edit during execution.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh"
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0118"

check "AC1: the six statuses map to their columns" lune run tests/run -- "$A/view.spec.luau"
check "AC2: ISO week changes on Monday and at the year boundary" lune run tests/run -- "$A/view.spec.luau"
check "AC3: only a raft with a done time counts its reviews" lune run tests/run -- "$A/view.spec.luau"
check "AC4: tokens split by model and a build row is ignored" lune run tests/run -- "$A/view.spec.luau"
check "AC5: the page tabs come from the view and the done window is bounded" lune run tests/run -- "$A/view.spec.luau"
check "AC6: the reader JSON splits the projects and dates the done commit" lune run tests/run -- "$A/view.spec.luau"
check "AC7: a z-nile issue is only on that tab, and the pickman tab exists" lune run tests/run -- "$A/tab.spec.luau"

finish
