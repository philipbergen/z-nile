#!/usr/bin/env bash
# Acceptance checks for {{ID}}. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

# check "AC1: <statement>" lune run tests/run -- tests/unit/<Feature>/<name>.spec.luau

finish
