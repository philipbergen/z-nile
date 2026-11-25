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
# AC1-AC4: the tooling's own specs (z-nile/tests/tooling), written with the code in #757 and on main. AC5-AC6: the
# sequestered specs of this closing's prep. Each spec runs once.
check "AC1: the easy path's rules as pure texts and facts (note, light rule, Level reader, guard list, ready, walk, contract risk, trace)" lune run tests/run -- tests/tooling/easy-path.spec.luau
check "AC2: the light path end to end, the raise journey and the easy design model included" lune run tests/run -- tests/tooling/light-path.spec.luau
check "AC3: the publish guard's raise exception and the light claim" lune run tests/run -- tests/tooling/light-publish.spec.luau
check "AC4: the gates that stood before are unchanged (ready, held units, rounds by level, the skills' wording)" lune run tests/run -- tests/tooling/readycheck.spec.luau tests/tooling/work-held.spec.luau tests/tooling/rounds-work-next.spec.luau tests/tooling/rounds-skills.spec.luau
check "AC5: the skills state the easy path's drafting rules (test with the code, red first; no acceptance folder, experiments or size)" lune run tests/run -- "$A/easy-skills.spec.luau"
check "AC6: the protected list holds every file the easy path and the light path rely on, lightready included" lune run tests/run -- "$A/guard-list.spec.luau"

finish
