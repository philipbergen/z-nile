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
check "AC2: a writing ./zn command refuses over unmerged paths, a whole conflict in a working file, or an unreadable registry, naming each path and the recovery, and writes nothing; the conflict-OK commands still run" \
  lune run tests/run -- "$A/conflicts.spec.luau"
check "AC3: c0115's rename-lesson-ids and rewrite-finished refuse, before writing, over unmerged paths and over a whole conflict in a working file" \
  lune run tests/run -- "$A/scripts.spec.luau"
check "AC4: ./zn audit reports a whole conflict in a file under a root or a skills folder as an error naming the path, line and recovery" \
  lune run tests/run -- "$A/audit.spec.luau"

finished refuse over unmerged paths, before writing" \
  lune run tests/run -- "$A/conflicts.spec.luau"

finish
