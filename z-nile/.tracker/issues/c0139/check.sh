#!/usr/bin/env bash
# Acceptance checks for c0139. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0139 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0139"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a whole merge conflict (an opener and a later closer at line starts) is recognised, and nothing else is" \
  lune run tests/run -- "$A/markers.spec.luau"
check "AC2: a writing ./zn command refuses over unmerged paths or a committed conflict, naming each path, and writes nothing; read-only commands still work" \
  lune run tests/run -- "$A/conflicts.spec.luau"
check "AC3: c0115's rename-lesson-ids and rewrite-finished refuse over unmerged paths, before writing" \
  lune run tests/run -- "$A/conflicts.spec.luau"

finish
