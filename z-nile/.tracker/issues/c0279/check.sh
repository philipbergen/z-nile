#!/usr/bin/env bash
# Acceptance checks for c0279. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0279 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0279"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the stop and cap cases prove the kill by the grandchild's pid, the stall limit only a real stall reaches, the fakes hold" bash "$A/pins.sh"
# a slow machine, simulated: the stop and the push wait 3 s (over the old stall limit of 2 s and the old 3 s wait)
# inside the step before their slow work, and every case of the dispatch spec still passes
check "AC2: with the fakes delayed 3 s the whole dispatch spec passes" env FAKE_DELAY=3 lune run tests/run -- tests/acceptance/c0117/dispatch-cli.spec.luau
# the promoted spec is exactly the reviewed text (zz-test, narrowing-pins-the-whole-file): its blob is the reviewed blob,
# and its diff from the branch's merge base with origin/main (less git's index line) is the golden diff, the readable
# record of what changed. A base that moved, or any other edit, a deleted assertion included, fails one of the two.
check "AC3: the dispatch-cli spec is the reviewed text and differs from main by exactly the reviewed diff" bash -c '[[ $(git hash-object tests/acceptance/c0117/dispatch-cli.spec.luau) == "de94e4b62763e856f4037743833672bbcb4edf04" ]] && diff <(git diff "$(git merge-base HEAD origin/main)" -- tests/acceptance/c0117/dispatch-cli.spec.luau | grep -v "^index ") "$1"' _ "$A/dispatch-cli.spec.expected.diff"

finish
