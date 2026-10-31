#!/usr/bin/env bash
# Acceptance checks for c0150. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the project's home
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0150 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0150"

check "AC1: f0104's key map and f0101's camera case are exactly the narrowed specs (the ten bindings, more keys allowed each with an action of its own, F free; Hop.rise of the hop at the shown tick, more arguments allowed), and their check.sh files still run them" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC2: the two narrowed specs pass on the code as it is" lune run tests/run -- tests/acceptance/f0104/keys.spec.luau tests/acceptance/f0101/place.spec.luau
check "AC3: f0104's and f0101's acceptance checks pass" bash -c 'bash "$("$ZN_ROOT/zn" find f0104)/check.sh" && bash "$("$ZN_ROOT/zn" find f0101)/check.sh"'

finish
