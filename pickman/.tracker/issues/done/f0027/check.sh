#!/usr/bin/env bash
# Acceptance checks for f0027. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0027 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0027"

# Narrowed by c0182 (for d0149's touch circles): swipe.spec.luau (AC1) and track.spec.luau (AC2) removed;
# d0149/acceptance/fold.spec.luau owns the touch fold and steer circle.
check "AC3: Controls feeds touches through the fold, omits gameProcessed, and the keyboard path stays" lune run tests/run -- "$A/place.spec.luau"
check "AC4: Touch is a Logic feature with unit specs and a declared edge to View" \
	bash -c 'test -f src/shared/Logic/Touch/init.luau || { echo "missing src/shared/Logic/Touch/init.luau"; exit 1; }; find tests/unit/Touch -name "*.spec.luau" | grep -q . || { echo "missing tests/unit/Touch spec"; exit 1; }; lune run tests/run -- tests/meta/architecture.spec.luau'

check "AC5: touch positions are converted to screen pixels before the fold sees them" lune run tests/run -- "$A/screen.spec.luau"

finish
