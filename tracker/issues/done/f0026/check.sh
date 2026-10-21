#!/usr/bin/env bash
# Acceptance checks for f0026. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0026 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0026"

check "AC1: the lobby switches all, day and week without changing the panel cap or the empty state" lune run tests/run -- "$A/lobby.spec.luau"
check "AC2: the rank line follows the run and ignores a stale packet" lune run tests/run -- "$A/flow.spec.luau"
check "AC3: a client score is not a board id, and the read cache rate-limits" lune run tests/run -- "$A/read.spec.luau"
check "AC4: Board and Rank are created in code, and the pinned lobby and flow adapters stay valid" lune run tests/run -- "$A/adapters.spec.luau"
check "AC5: a submitted score shows on the all-time panel and the day board, and ranks once" lune run tests/run -- "$A/endtoend.spec.luau"

finish
