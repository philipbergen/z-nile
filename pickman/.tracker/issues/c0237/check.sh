#!/usr/bin/env bash
# Acceptance checks for c0237. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0237 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0237"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the lobby tooling spec still passes" lune run tests/run -- tests/acceptance/f0061/lobby-tooling.spec.luau
check "AC2: no pattern in it escapes a brace, which luau-lsp rejects" bash -c '! grep -nF -e "%{" -e "%}" tests/acceptance/f0061/lobby-tooling.spec.luau' 

finish
