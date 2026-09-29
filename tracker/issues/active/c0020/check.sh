#!/usr/bin/env bash
# Acceptance checks for c0020. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance" # sequestered specs; see the testing skill
source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "AC1: resolveRequire follows Roblox require-by-string semantics" lune run tests/run -- "$A/resolve-require.spec.luau"
check "AC2: built place satisfies structural rules" lune run tests/run -- "$A/place-rules.spec.luau"
check "AC3: affected selects place specs for src/ and project changes" lune run tests/run -- "$A/affected-place.spec.luau"

finish
