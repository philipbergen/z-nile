#!/usr/bin/env bash
# Acceptance checks for {{ID}}. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

A="$(dirname "${BASH_SOURCE[0]}")/acceptance" # sequestered specs; see the testing skill

# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"

finish
