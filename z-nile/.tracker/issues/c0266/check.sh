#!/usr/bin/env bash
# Acceptance checks for c0266. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0266 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0266"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

# AC3, check-only (one run of a slow-tier spec, about 270 s, never promoted): the promoted classified spec runs all
# five of its cases, and neither the case c0266 rewrites nor the chores-only case it replaces is among the failures.
# Its first two cases are red on main since #383 for a reason outside c0266 (two rafts share the slug
# capture-interview-and-idea-review: R0106 and the retired R0091; c0266's Non-goals), so its other failures are not
# judged here.
classified_case() {
  local out
  out=$(lune run tests/run -- tests/acceptance/c0114/classified.spec.luau 2>&1)
  printf '%s\n' "$out" | tail -n 12
  printf '%s\n' "$out" | grep -qE '^[0-9]+ passed, [0-9]+ failed, 1 spec files$' || { echo "AC3: the run printed no summary"; return 1; }
  local passed failed
  passed=$(printf '%s\n' "$out" | sed -nE 's/^([0-9]+) passed, ([0-9]+) failed, 1 spec files$/\1/p')
  failed=$(printf '%s\n' "$out" | sed -nE 's/^([0-9]+) passed, ([0-9]+) failed, 1 spec files$/\2/p')
  [[ $((passed + failed)) -eq 5 ]] || { echo "AC3: expected 5 cases, ran $((passed + failed))"; return 1; }
  if printf '%s\n' "$out" | grep -qF "classified.spec.luau :: z-nile's root holds chores, features and defects, each typed by its id"; then
    echo "AC3: the rewritten case failed"; return 1
  fi
  if printf '%s\n' "$out" | grep -qF "no feature or defect is filed in z-nile's root"; then
    echo "AC3: the chores-only case still runs"; return 1
  fi
}

check "AC1: the promoted classified spec is exactly its rewritten text" \
	lune run tests/run -- "$A/pinned.spec.luau"
check "AC2: the skills and the README let z-nile's root hold chores, features and defects" \
	lune run tests/run -- "$A/docs.spec.luau"
check "AC3: a run of the promoted classified spec passes its rewritten case" classified_case

finish
