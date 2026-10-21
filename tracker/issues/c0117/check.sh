#!/usr/bin/env bash
# Acceptance checks for c0117. SEQUESTERED: never edit during execution.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh"
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0117"

check "AC1: a closer file replaces only the keys it sets" lune run tests/run -- "$A/models.spec.luau"
check "AC2: the higher rank wins whole" lune run tests/run -- "$A/models.spec.luau"
check "AC3: equal rank uses the larger cap" lune run tests/run -- "$A/models.spec.luau"
check "AC4: script steps stay script and z-design stays model" lune run tests/run -- "$A/models.spec.luau"
check "AC5: render, an empty model cell, and appendOnly" lune run tests/run -- "$A/models.spec.luau"
check "AC6: a missing rank, an unknown runtime, and an unnamed skill are errors" lune run tests/run -- "$A/models.spec.luau"
check "AC7: dry-run prints the plan and spend and commit store the model" lune run tests/run -- "$A/models.spec.luau"

finish
