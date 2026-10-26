#!/usr/bin/env bash
# Acceptance checks for c0141. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0141 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0141"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: check-paths' Touched exemption compares a path's repository-relative form with what each Touched entry names, read one way chosen from the entry's own text, and never exempts a path that climbs above the checkout" \
  lune run tests/run -- "$A/touched-from-home.spec.luau"
check "AC2: c0120's promoted check-paths spec takes its scan from z-nile/tests/acceptance/c0120/checkpaths.luau and defines no scanner of its own" \
  lune run tests/run -- "$A/uses-module.spec.luau"
check "AC3: c0120's check-paths spec still passes, live scan included" \
  bash -c 'test -f tests/acceptance/c0120/checkpaths.luau && lune run tests/run -- tests/acceptance/c0120/check-paths.spec.luau'

finish
