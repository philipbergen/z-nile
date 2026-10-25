#!/usr/bin/env bash
# Acceptance checks for f0017. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0017 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0017"

check "AC1: a power pellet starts the level's frightened period, restarts it when eaten again, and it ends" lune run tests/run -- "$A/power.spec.luau"
check "AC2: a whole run plays through Session headless, deterministically" lune run tests/run -- "$A/full-run.spec.luau"

finish
