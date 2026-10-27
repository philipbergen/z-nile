#!/usr/bin/env bash
# Acceptance checks for d0151. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0151 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0151"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"

check "AC1: f0027's, f0028's and f0029's promoted touch specs pass" lune run tests/run -- tests/acceptance/f0027/*.spec.luau tests/acceptance/f0028/*.spec.luau tests/acceptance/f0029/*.spec.luau
finish
