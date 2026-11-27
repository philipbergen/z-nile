#!/usr/bin/env bash
# Acceptance checks for c0182. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0182 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0182"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the four touch specs with no surviving rule are removed (and dropped from their owners' check.sh), and all 18 narrowed touch specs are exactly the narrowed files pinned whole by digest with their owners' check.sh still running them" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC2: all 18 narrowed specs pass on the code as it is (with F0158_EXACT=1)" env F0158_EXACT=1 lune run tests/run -- tests/acceptance/f0027/place.spec.luau tests/acceptance/f0027/screen.spec.luau tests/acceptance/f0028/look.spec.luau tests/acceptance/f0028/place.spec.luau tests/acceptance/f0029/button.spec.luau tests/acceptance/f0029/jump.spec.luau tests/acceptance/f0029/phone.spec.luau tests/acceptance/f0029/place.spec.luau tests/acceptance/f0110/adapters.spec.luau tests/acceptance/f0110/buttons.spec.luau tests/acceptance/f0110/fold.spec.luau tests/acceptance/f0126/controls.spec.luau tests/acceptance/f0126/parts.spec.luau tests/acceptance/f0126/touch.spec.luau tests/acceptance/f0143/controls.spec.luau tests/acceptance/f0143/place.spec.luau tests/acceptance/f0158/clear.spec.luau tests/acceptance/c0155/narrowed.spec.luau
check "AC3: all eight owners' acceptance checks (f0027, f0028, f0029, f0110, f0126, f0143, f0158, c0155) pass" bash -c 'for id in f0027 f0028 f0029 f0110 f0126 f0143 f0158 c0155; do bash "$("$ZN_ROOT/zn" find "$id")/check.sh" || exit 1; done'

finish
