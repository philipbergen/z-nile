#!/usr/bin/env bash
# Acceptance checks for c0114. SEQUESTERED: never edit during execution.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh"
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0114"

check "AC1: projects.toml lists pickman then z-nile" lune run tests/run -- "$A/home.spec.luau"
check "AC2: --project writes project z-nile under tracker/issues" lune run tests/run -- "$A/home.spec.luau"
check "AC3: no flag writes project pickman" lune run tests/run -- "$A/home.spec.luau"
check "AC4: missing file is pickman; a repeated or empty list errors" lune run tests/run -- "$A/home.spec.luau"
check "AC5: list --project z-nile omits a pickman issue" lune run tests/run -- "$A/home.spec.luau"
check "AC6: an unknown project publishes nothing" lune run tests/run -- "$A/home.spec.luau"
check "AC7: an emergent issue copies the raft project" lune run tests/run -- "$A/home.spec.luau"

finish
