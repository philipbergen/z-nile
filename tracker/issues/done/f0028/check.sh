#!/usr/bin/env bash
# Acceptance checks for f0028. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0028 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0028"

check "AC1: a look-zone move is a pixel delta applied by View.look" lune run tests/run -- "$A/look.spec.luau"
check "AC2: a touch that begins on the snap control is snap, and a far edge is look only on the right half" lune run tests/run -- "$A/hit.spec.luau"
check "AC3: the mouse delta reaches View.look only when no touch is holding it and this frame has not looked" lune run tests/run -- "$A/place.spec.luau"

finish
