#!/usr/bin/env bash
# Acceptance checks for f0197. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0197 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0197"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a title's stores are named from its prefix, and pickman's prefix \"\" keeps today's names" \
  lune run tests/run -- "$A/names.spec.luau" "$A/store.spec.luau"
check "AC2: every row records the run's revives and every row read shows them, 0 for a row stored before; revives never rank or replace" \
  lune run tests/run -- "$A/revives.spec.luau" "$A/top.spec.luau"
check "AC3: HiscoreGames gives each title its own prefix and names its progress figure, stored as the row's level" \
  lune run tests/run -- "$A/games.spec.luau"
check "AC4: one generic Boards server adapter writes and serves one title's boards, with revives, on its own stores" \
  lune run tests/run -- "$A/boards.spec.luau" "$A/write.spec.luau" "$A/serve.spec.luau"
check "AC5: the library's Hiscores keeps pickman's rules: periods, replace, rows, retries, run policy, the shared read and the list" \
  lune run tests/run -- "$A/period.spec.luau" "$A/replace.spec.luau" "$A/rows.spec.luau" "$A/drive.spec.luau" \
  "$A/run.spec.luau" "$A/leave.spec.luau" "$A/read.spec.luau" "$A/drivetop.spec.luau"

finish
