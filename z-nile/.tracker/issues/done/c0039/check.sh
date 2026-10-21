#!/usr/bin/env bash
# Acceptance checks for c0039. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance" # sequestered specs; see the testing skill
source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"

# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"

finish
