#!/usr/bin/env bash
# Acceptance checks for c0153. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0153 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0153"

check "AC1: plain data and a JSON round trip within 1e-9, the one-ulp-off value included" lune run tests/run -- "$A/plain.spec.luau"
check "AC2: f0032's frame case uses the helper and still passes" lune run tests/run -- "$A/plain.spec.luau" tests/acceptance/f0032/frame.spec.luau

finish
