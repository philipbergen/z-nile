#!/usr/bin/env bash
# Acceptance checks for c0435. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0435 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0435"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The specs are the tooling's own (z-nile/tests/tooling), written with the code; each runs once.
check "AC1: the easy path rules (short note, Level line, guard list, ready, contract risk, work walk)" lune run tests/run -- tests/tooling/easy-path.spec.luau
check "AC2: the light path end to end, the raise journey included" lune run tests/run -- tests/tooling/light-path.spec.luau
check "AC3: the refusals that must stay (ready, the walk, rounds, the skills' wording)" lune run tests/run -- tests/tooling/readycheck.spec.luau tests/tooling/work-held.spec.luau tests/tooling/rounds-skills.spec.luau

finish
