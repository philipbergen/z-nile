#!/usr/bin/env bash
# Acceptance checks for f0100. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0100 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0100"

check "AC1: parse builds a maze whose queries match the text" lune run tests/run -- "$A/parse.spec.luau"
check "AC2: parse rejects malformed text, naming the problem and where" lune run tests/run -- "$A/validate.spec.luau"
check "AC3: the classic layout is the designed 28x31 map" lune run tests/run -- "$A/classic.spec.luau"
check "AC4: heading conventions" lune run tests/run -- "$A/conventions.spec.luau"

finish
