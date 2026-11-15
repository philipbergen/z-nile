#!/usr/bin/env bash
# Acceptance checks for c0226. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0226 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0226"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: ids.cutFile, the one rule history and trail.cuts judge compactions by, counts a map changed in place, a map added, a map moved and changed in one commit (named by the file it moved to) and a map moved with its lines reordered, and no plain move, deletion or commit without a map; ids.mapPatchLine, the one reader both read a map's patch through, marks an added and a deleted map and keeps the content lines but the +++/--- headers and the No newline line" \
  lune run tests/run -- "$A/rule.spec.luau"
check "AC2: trail.cuts, over a real repository and the head and folder it is given, lists every commit that adds, changes, moves and changes, or moves and reorders a map (the move-and-change one a commit git's -M pairs as a rename), each with the map file that makes it one, and no plain move or deletion, and exactly the commits history counts as compactions; a move that only drops the map's final newline is none" \
  lune run tests/run -- "$A/cuts.spec.luau"
check "AC3: the trail module's header, history's header comment and the lesson item-history-spans-moves-and-compaction say a move that changes the map is a compaction, and none says trail.cuts reads the map with renames" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC4: the promoted specs that pin history's compactions and the trail with no pushing fixture (c0118 history and model, c0111 trail) still pass unchanged" \
  lune run tests/run -- tests/acceptance/c0118/history.spec.luau tests/acceptance/c0118/model.spec.luau tests/acceptance/c0111/trail.spec.luau

finish
