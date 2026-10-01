#!/usr/bin/env bash
# Acceptance checks for c0020. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0020 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0020"

check "AC1: resolveRequire follows Roblox require-by-string semantics" lune run tests/run -- "$A/resolve-require.spec.luau"
check "AC2: built place satisfies structural rules" lune run tests/run -- "$A/place-rules.spec.luau"
check "AC3: affected selects place specs for src/ and project changes" lune run tests/run -- "$A/affected-place.spec.luau"

finish
