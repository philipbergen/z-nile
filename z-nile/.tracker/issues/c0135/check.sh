#!/usr/bin/env bash
# Acceptance checks for c0135. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0135 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0135"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1-AC4: new issue and new raft refuse a used slug of their kind, audit reports a shared one, and the skills say so" \
  lune run tests/run -- "$A/slugs.spec.luau"
check "AC5: the real tracker audits clean (no two items of one kind share a slug)" "$ZN_ROOT/zn" audit
check "AC6: c0114's classification spec still holds every slug once" lune run tests/run -- tests/acceptance/c0114/classified.spec.luau

finish
