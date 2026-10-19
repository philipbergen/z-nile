#!/usr/bin/env bash
# Acceptance checks for c0103. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0103 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0103"

check "AC1: f0014's key-map spec pins only W, A, S and D and the shape of the map, not the arrows, Space or the key count" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC2: the narrowed key-map spec and the View unit spec pass on the code as it is" lune run tests/run -- tests/acceptance/f0014/keys.spec.luau tests/unit/View/view.spec.luau
check "AC3: f0014's acceptance checks pass" bash "$(scripts/tracker.sh find f0014)/check.sh"

finish
