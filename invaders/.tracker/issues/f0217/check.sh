#!/usr/bin/env bash
# Acceptance checks for f0217. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0217 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0217"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: two players at the two ends of one field twice as deep, facing each other, each with their own cannon, 3 lives, four bunkers and a group of 5 x 8" lune run tests/run -- "$A/field.spec.luau"
check "AC2: each wave flies in from the east side along the midline in single file, peels off alternately into the two groups, forms in about 3 s, and can be shot on the way" lune run tests/run -- "$A/flyin.spec.luau"
check "AC3: a shot crosses the whole field, hitting either group, the ship and the other player's barriers, and stops at the other player's base line unless shots may hit players" lune run tests/run -- "$A/crossing.spec.luau"
check "AC4: each group marches and fires at its own player by the solo rules; own score, lives and revives; a hit or a game over is that player's alone; a wave ends when both groups are gone" lune run tests/run -- "$A/sides.spec.luau"
check "AC5: a player whose run ends with no revive leaves with their group, later waves come to the survivor as one solo formation, and the match ends when both are out" lune run tests/run -- "$A/survivor.spec.luau"
check "AC6: a seeded, deterministic, JSON-safe match that reads each player's input alone and plays to its end" lune run tests/run -- "$A/match.spec.luau"
check "AC7: every Logic feature is engine-free, requires only declared edges and has unit specs" lune run tests/run -- tests/meta/architecture.spec.luau

finish
