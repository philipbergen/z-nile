#!/usr/bin/env bash
# Acceptance checks for c0288. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0288 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0288"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# pins.sh finds c0260's specs itself (`./zn find c0260`: its acceptance/ folder, or tests/acceptance/c0260 once it is
# done), so no literal path to another item is named here. The floor, 120 s, is c0279's limit "only a real stall
# reaches"; it is passed from here so that it is in the approved contract (design review 001 F5).
check "AC1: every stall or tool limit c0260's specs set is at least 120 s, or marked as a case that tests a stall (# tests a stall), and none is set in a form the pin cannot read" bash "$A/pins.sh" limits 120
# the whole change (zz-test, narrowing-pins-the-whole-file, as a shape: c0260's redesign moves the blobs): from the
# branch's merge base with origin/main, c0260's specs change only in limit lines, each added one at least 120 s and
# unmarked; no spec added, deleted or renamed. An empty change (c0260 shipped the limits itself) passes.
check "AC2: the branch changes c0260's specs only in limit lines, each added one at least 120 s and unmarked, and adds, deletes or renames no spec" bash "$A/pins.sh" shape 120

finish
