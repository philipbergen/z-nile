#!/usr/bin/env bash
# Acceptance checks for c0172. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0172 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0172"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the only Actions workflow publishes the place and does not run the gate or the runtime tests" \
	lune run tests/run -- "$A/deploy.spec.luau"
check "AC2: deliver and merge on the local full gate, and the skills do not send the agent to Actions" \
	lune run tests/run -- "$A/merge.spec.luau"
check "AC3: the narrowed promoted specs are exactly the narrowed text" \
	lune run tests/run -- "$A/narrowed.spec.luau"
check "AC4: the cicd command reserves the CICD places, publishes them, and runs both runtime suites" \
	bash -c 'cd "$ZN_ROOT/pickman" && lune run tests/run -- "$1"' cicd "../${A#"$ZN_ROOT/"}/cicd.spec.luau"

finish
