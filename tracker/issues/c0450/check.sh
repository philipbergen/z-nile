#!/usr/bin/env bash
# Acceptance checks for c0450. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance" # sequestered specs; see the testing skill
source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "AC1: ticket-prep step 3 has the Override check, before Test plan" lune run tests/run -- "$A/override-check.spec.luau"
check "AC2: design-mode review rates an unnamed override high" lune run tests/run -- "$A/override-check.spec.luau"
check "AC3: the issue template has a visible Overrides line outside its comment" lune run tests/run -- "$A/override-check.spec.luau"
check "AC4: the acceptance spec is formatted and linted" bash -c 'stylua --check "$0" && selene --quiet "$0"' "$A"
check "AC5: the full gate passes" scripts/check.sh --full

finish
