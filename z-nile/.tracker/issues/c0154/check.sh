#!/usr/bin/env bash
# Acceptance checks for c0154. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0154 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0154"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
S="$A/schedule.spec.luau"
check "AC1: the runner takes unrecorded spec files first, then recorded ones slowest first, ties by path" lune run tests/run -- "$S"
check "AC2: the duration record is read and written by one rule, merged across runs, rewritten only when a run had the home's own files, cleaned of gone files on a full run, and a malformed or empty record is refused whole and replaced" lune run tests/run -- "$S"
check "AC3: on a real run's 177 file times, slowest first ends at least a fifth sooner than path order on 8 lanes" lune run tests/run -- "$S"
check "AC4: the runner starts the slowest recorded file first, records only the home's tests/ files, and reports in path order with unchanged counts and exit code, a file listed twice included" lune run tests/run -- "$S"
# promoted specs (every project's tests/acceptance) are unchanged, c0154's own promoted folder aside
promoted_unchanged() {
  local changed
  changed=$(git -C "$ZN_ROOT" diff --name-only origin/main...HEAD -- "$ZN_ROOT/pickman/tests/acceptance" "$ZN_ROOT/z-nile/tests/acceptance" | grep -v '^z-nile/tests/acceptance/c0154/' || true)
  [[ -z $changed ]] || { echo "promoted specs changed: $changed"; return 1; }
}
check "AC5: no promoted spec changes" promoted_unchanged

finish
