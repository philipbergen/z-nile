#!/usr/bin/env bash
# Acceptance checks for c0287. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0287 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0287"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the orphan, late and review-waiting fakes hold the reviewed shape, every fake marks its start, c0279's pins hold, and c0117's specs outside dispatch-cli wait only through their wall-clock helpers" bash "$A/pins.sh"
# a slow machine, simulated: every CLI fake waits 3 s before its first output and an author 12 s more before its
# nested review starts; control-cli and trackerstate still pass (run without a dispatched step's variables: slow.sh)
check "AC2: with the fakes delayed (FAKE_DELAY=3, FAKE_START_DELAY=12) control-cli and trackerstate pass" bash "$A/slow.sh"
# the promoted specs and the shared fake are exactly the reviewed text (zz-test, narrowing-pins-the-whole-file): each
# file's diff from the branch's merge base with origin/main, less git's index line and the hunks' line numbers (so an
# unrelated change that landed above a hunk first does not move it), is its golden diff. Any other edit, a deleted or
# an added line included, or a fake mode's timing cut (the review fakes' 16, 18 and 20 s), fails it. In a raft, c0287
# sits below every member that changes these files (Implementation step 0).
check "AC3: control-cli, trackerstate and the fake differ from main by exactly the reviewed diffs" bash -c 'b=$(git merge-base HEAD origin/main) || exit 1; for f in acceptance/c0117/control-cli.spec acceptance/c0117/trackerstate.spec lib/fakecli; do diff <(git diff "$b" -- "tests/$f.luau" | grep -v "^index \|^@@") "$1/${f##*/}.luau.expected.diff" || exit 1; done' _ "$A"

finish
