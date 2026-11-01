#!/usr/bin/env bash
# Acceptance checks for c0138. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0138 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0138"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: trail.renamed names both sides of every pair whose sides differ in a compaction map and nothing else, is nil for a map that does not parse, and trail.renames reads a commit that git can't read as unreadable" \
  lune run tests/run -- "$A/renamed.spec.luau"
check "AC2: a compaction that keeps an id and rewrites its document in place starts no new life (capture, and a first-review lookup, still find the item's past), and one that renames the id, gives it to another item, repeats its pair or leaves a map that does not parse does, marked, and so does an item that first appears in a commit that changed the map; a later compaction whose map keeps an id an earlier one renamed does not restart it again; a commit that changes more than one map file reads each, and one it can't read or that does not parse restarts the item; trail.renames reads the ids a commit renames from the map files that commit changed, and a commit that changed none as unreadable" \
  lune run tests/run -- "$A/kept.spec.luau"
check "AC3: the trail module's header, the capture row of the zz-rules skill and the lesson item-history-spans-moves-and-compaction state the same rule" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC4: the promoted specs that read the trail (c0111 trail, c0114 trail-move, c0119 capture-cli) still pass unchanged" \
  lune run tests/run -- tests/acceptance/c0111/trail.spec.luau tests/acceptance/c0114/trail-move.spec.luau tests/acceptance/c0119/capture-cli.spec.luau

finish
