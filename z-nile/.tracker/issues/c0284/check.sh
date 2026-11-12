#!/usr/bin/env bash
# Acceptance checks for c0284. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0284 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0284"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the board model carries each item's provenance, equal to ./zn who's lines for every kind of item, and the item view (run in node) writes escaped rows in the model's order for an issue and a raft and none without entries" \
  lune run tests/run -- "$A/board.spec.luau"
check "AC2: the model is built from the checkout it is given, not the folder it runs in" \
  lune run tests/run -- "$A/board.spec.luau"
check "AC3: the page build reads the history once: one mainline, people and cuts log, one cat-file --batch and one read of every merge's second parent, for any number of items" \
  lune run tests/run -- "$A/board.spec.luau"
check "AC4: a provenance.md or an issue spend.md that does not parse is named in problems, shows no provenance, and leaves every other item unchanged" \
  lune run tests/run -- "$A/board.spec.luau"
check "AC5: a board with no git of its own carries the stored rows alone, an item with none has no provenance key, a shallow clone shows what who prints, and commits are bucketed by item folder" \
  lune run tests/run -- "$A/board.spec.luau"
check "AC6: zz-rules and the README name the section, the promoted specs this layer touches stay green and the real tree audits and lessons-checks clean" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- "$1" tests/acceptance/c0042/model.spec.luau tests/acceptance/c0042/page.spec.luau tests/acceptance/c0118/model.spec.luau tests/acceptance/c0118/page.spec.luau tests/acceptance/c0118/view.spec.luau tests/acceptance/c0070/board-refresh.spec.luau tests/acceptance/c0115/docs.spec.luau tests/acceptance/c0116/docs.spec.luau tests/tooling/board.spec.luau tests/tooling/board-review.spec.luau' _ "$A/docs.spec.luau"

finish
