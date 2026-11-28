#!/usr/bin/env bash
# Acceptance checks for f0421. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0421 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0421"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"

check "AC28: today's root table answers as pinned" lune run tests/run -- tests/tooling/models-pin.spec.luau
check "AC29: the catalog, the lists and the consent record parse and refuse" lune run tests/run -- tests/tooling/models-catalog.spec.luau
check "AC30: identity over every listed id" lune run tests/run -- tests/tooling/models-identity.spec.luau
check "AC31: a session's model is declared by the person" lune run tests/run -- tests/tooling/work-can.spec.luau

finish
