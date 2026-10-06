#!/usr/bin/env bash
# Acceptance checks for c0098. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root

# the variable name is split so this file does not name it (R0021's gate scans every check.sh)
check "AC1: the tracker code uses no index plumbing" bash -c '
  ! grep -rnE "GIT_INDEX_""FILE|read-tree|update-index|write-tree" scripts/tracker/'
check "AC2: the remap specs pass" lune run tests/run -- tests/acceptance/c0081/remap.spec.luau tests/tooling/remap-once.spec.luau

finish
