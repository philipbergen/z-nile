#!/usr/bin/env bash
# Acceptance checks for f0220. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0220 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0220"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a 1,024 x 768 wrap-around field: every body wraps, distances run the short way across the wrap, and a move is checked along its whole length" lune run tests/run -- "$A/field.spec.luau"
check "AC2: the ship turns 3 headings a tick, thrusts 0.1 along its new heading with inertia, loses 1% a tick to drag and never passes 6 a tick" lune run tests/run -- "$A/ship.spec.luau"
check "AC3: up to 4 shots from the nose at 8 a tick plus the ship's velocity, each flying 60 ticks and wrapping, hitting the nearest target along its move" lune run tests/run -- "$A/shots.spec.luau"
check "AC4: rocks split large into 2 medium into 2 small, scoring 20, 50 and 100; ramming one costs a life and the rock still splits and scores" lune run tests/run -- "$A/rocks.spec.luau"
check "AC5: the large saucer (200) fires at random, the small (1,000) aims at the ship, closer as the score rises, and comes more often in later waves; both cross edge to edge" lune run tests/run -- "$A/saucers.spec.luau"
check "AC6: hyperspace puts the ship at a random spot for 30 ticks, and it explodes on re-entry 1 time in 6" lune run tests/run -- "$A/hyperspace.spec.luau"
check "AC7: 3 lives and one more every 10,000; a lost ship comes back at the centre once it is clear, protected 120 ticks; the last life lost is game over" lune run tests/run -- "$A/lives.spec.luau"
check "AC8: wave 1 has 4 large rocks and each later wave 2 more, up to 11, on the edges clear of the ship; the next wave starts 120 ticks after the last rock" lune run tests/run -- "$A/waves.spec.luau"
check "AC9: a seeded, deterministic, JSON-safe run at 60 ticks a second, whose events carry their kinds' fields" lune run tests/run -- "$A/game.spec.luau"
check "AC10: every Logic feature is engine-free, requires only declared edges and has unit specs" lune run tests/run -- tests/meta/architecture.spec.luau

finish
