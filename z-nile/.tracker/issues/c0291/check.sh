#!/usr/bin/env bash
# Acceptance checks for c0291. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0291 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0291"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a lesson's text is its file then its notes in name order, a note is named <date>-<label>.md, and check judges the file and refuses an orphan, misnamed or empty note" lune run tests/run -- "$A/notes.spec.luau"
check "AC2: notes added on two branches merge cleanly with both kept and read in name order, two edits of a check and two texts of one note name still conflict, and lessons --check names orphan, nested, misnamed and empty notes" lune run tests/run -- "$A/notes-merge.spec.luau"
check "AC3: a prep PR may carry a lesson or a note in their own shapes, and nothing else under lessons/" lune run tests/run -- "$A/notes-paths.spec.luau"
check "AC4: zz-rules Items states the note file, its merge, its reading and checks and the conflict that stays, and every skill's Lessons bullet says a note is a file" lune run tests/run -- "$A/notes-docs.spec.luau"
check "AC5: lessons --check passes on the tree" ../zn lessons --check

finish
