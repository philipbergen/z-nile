#!/usr/bin/env bash
# Acceptance checks for c0063. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0063 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0063"

check "AC1: f0031's specs no longer pin the play-again surface, and keep (narrowed) everything that stays true" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC2: f0031's acceptance checks pass on the code as it is" bash "$(./zn find f0031)/check.sh"

finish
