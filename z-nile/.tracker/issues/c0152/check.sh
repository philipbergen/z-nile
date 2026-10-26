#!/usr/bin/env bash
# Acceptance checks for c0152. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0152 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0152"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: ./zn merge-check exits 0 only when main's new commits are tracker state that edits no existing check.sh and touches none of the PR's files, and the merged tree, its own repository under TMPDIR, passes every listed tracker-reading stage; otherwise exits 1 naming each" \
  lune run tests/run -- "$A/merge-check.spec.luau"
check "AC2: zz-rules' Merging step 4 states the exception through ./zn merge-check and --match-head-commit, and the command table, the read-only list and the usage name it" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC3: z-nile/tests/merge-stages.txt is the one complete list of gate stages that read tracker files: every spec the search finds is run or skipped with a reason" \
  lune run tests/run -- "$A/stages.spec.luau"

finish
