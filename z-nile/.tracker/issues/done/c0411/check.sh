#!/usr/bin/env bash
# Acceptance checks for c0411. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered pins: here before `./zn done`, promoted to its project's tests/acceptance/c0411 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0411"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# Both checks are text pins: c0411 lands before d0406, while `./zn metrics` still crashes and rounds.spec cannot load, so
# no check here may run it. That the edited case passes, fails for a missing, doubled or misordered raft, and that
# c0116/retired.spec then passes is proved in prep (experiments/) and checked by d0406 (depends_on: [c0411]), whose AC7 runs both
# specs once after this lands: lune run tests/run -- tests/acceptance/c0043/rounds.spec.luau tests/acceptance/c0116/retired.spec.luau (2 to 5 min).
echo "AC1 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"
check "AC1: c0043/rounds.spec is its merge base with origin's main with exactly the two reviewed c0411 hunks, byte for byte (the projects require; the loop over every registered root and the four rafts folders), and a base that is not the stale form is refused" python3 "$A/narrow.py" "$ZN_ROOT"
check "AC2: c0116/retired.spec is unedited against its merge base with origin's main" bash -c '
  set -e
  tip=$(git -C "$1" ls-remote origin refs/heads/main | cut -f1)
  mb=$(git -C "$1" merge-base HEAD "$tip")
  git diff --quiet "$mb" -- tests/acceptance/c0116/retired.spec.luau # from the home (z-nile/), where ac.sh runs checks
' _ "$ZN_ROOT"

finish
