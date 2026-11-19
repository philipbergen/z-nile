#!/usr/bin/env bash
# Acceptance checks for d0412. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home

check "AC1: a decline during a revive's write that finds none held, or fails, opens no purchase screen, holds nothing, and the run ends at the next step" lune run tests/run -- tests/place/decline-during-revive.spec.luau

finish
