#!/usr/bin/env bash
# Acceptance checks for c0004. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "AC1: affected gate runs without --base under the host bash" bash z-nile/check.sh --affected

finish
