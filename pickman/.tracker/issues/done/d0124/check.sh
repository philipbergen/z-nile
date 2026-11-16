#!/usr/bin/env bash
# Acceptance checks for d0124. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/d0124 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0124"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
# adapters.spec holds the adapter cases of AC3 to AC6 (one stub engine for all of them), so each of those checks runs it
check "AC1: the all-time top-10 list of runs keeps the ten best runs of all players in order (score, level, earlier run, id), lets one player hold several places, lists each run id once, and starts from the stored per-player bests" lune run tests/run -- "$A/top.spec.luau"
check "AC2: Hiscores.driveTop writes a run to the list through the store's transform with drive's retries and budgets, merges every per-player best (its companion row, deduped by run id) on each write, never creates a list without them, and reports the run's place, that it missed the top N, or nothing" lune run tests/run -- "$A/drivetop.spec.luau"
check "AC3: one player's two runs in a row, the second lower, are heard as places 1 and 2, and the lobby's all-time answer lists both in order" lune run tests/run -- "$A/adapters.spec.luau"
check "AC4: game over shows the run's place on the list or NOT IN THE ALL-TIME TOP 10, through Ranks and FlowView" lune run tests/run -- "$A/flow.spec.luau" "$A/adapters.spec.luau"
check "AC5: the lobby's all-time answer is the stored list (or the per-player board while none is stored) plus the asker's own best, read at most once per CACHE_TTL per player and never twice at once, and dropped when they leave; day and week are unchanged and carry no best" lune run tests/run -- "$A/lobby.spec.luau" "$A/adapters.spec.luau"
check "AC6: HiscoreStore writes the per-player boards first and hands their all-time bests to the list, keys each run by user, clock, run and job id, hears the list's place, and still writes the per-player boards when the list fails" lune run tests/run -- "$A/adapters.spec.luau"
check "AC7: the existing hiscore, flow and lobby specs still pass" lune run tests/run -- tests/acceptance/f0024/*.spec.luau tests/acceptance/f0025/*.spec.luau tests/acceptance/f0026/*.spec.luau tests/acceptance/f0061/*.spec.luau tests/unit/Hiscores/*.spec.luau tests/unit/Flow/*.spec.luau tests/unit/Lobby/*.spec.luau

finish
