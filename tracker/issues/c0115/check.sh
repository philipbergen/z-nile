#!/usr/bin/env bash
# Acceptance checks for c0115. SEQUESTERED: never edit during execution.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh"
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0115"

check "AC1: pipeline skills have name and description" lune run tests/run -- "$A/names.spec.luau"
check "AC2: internal skills have name and description" lune run tests/run -- "$A/names.spec.luau"
check "AC3: README flowchart precedes the first paragraph" lune run tests/run -- "$A/names.spec.luau"
check "AC4: the old tracker skill stays, and AGENTS.md names z-ticket" lune run tests/run -- "$A/names.spec.luau"
check "AC5: the seven copy pairs match apart from name" lune run tests/run -- "$A/names.spec.luau"
check "AC6: z-run contains both source headings" lune run tests/run -- "$A/names.spec.luau"

finish
