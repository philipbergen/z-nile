#!/usr/bin/env bash
# Acceptance checks for c0177. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0177 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0177"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: f0125's speeds.spec is exactly the narrowed one (pinned whole), no compare of the shipped config against the classic tables, and no ghost speed without the ramp, is left, and f0125's check.sh still runs it" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC2: f0125's acceptance checks pass" bash -c 'bash "$("$ZN_ROOT/zn" find f0125)/check.sh"'

finish
