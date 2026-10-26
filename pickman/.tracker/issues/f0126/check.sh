#!/usr/bin/env bash
# Acceptance checks for f0126. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the project's home
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0126 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0126"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: Picks: interior walls clear of the house and beside a walkable tile can be marked, three at a time by a seeded roll; the wall beside a tile ahead, left, right, behind; a pick is a hunting ghost's ten tiles, half when fast; six boons at even odds" lune run tests/run -- "$A/picks.spec.luau"
check "AC2: Maze.open makes one interior wall empty in a copy with the same id, size and spawn, and refuses a non-wall and an edge wall" lune run tests/run -- "$A/maze.spec.luau"
check "AC3: in the session, Pick stops the player beside a marked wall and stands them 43 steps; the wall opens (and can be walked into), another is marked, a boon is granted and the player goes on; a movement key, a hop or leaving play wastes it; the request lapses on its 25th step; holes stay over a death and close on a new level or a new run" lune run tests/run -- "$A/pick.spec.luau"
check "AC4: each boon does what it says: long hops (their own cool-down, no pick in their air) over a death until a new level, a half-time next pick kept until a new run, a power period and a double one, one more shot, every pellet and power pellet back; the six come up evenly" lune run tests/run -- "$A/boons.spec.luau"
check "AC5: Movement halts and resumes, a hop has a length, a power period a factor, ghosts walk the opened maze; F is the pick key, marked walls are runs of their own, the frame's maze, walls key, pick bar and boon banner (placed clear of the HUD)" lune run tests/run -- "$A/parts.spec.luau"
check "AC6: the adapters, run on a stub engine and read: F sends View.PICK_INTENT with no new require in Controls; HudView places the bar and banner at the boxes, again on a new screen; MazeView builds the gold marks and keeps the holes open; Main rebuilds the walls once per change of the holes or the marks; show the long hop, rebuild the walls gold from the frame, give the radar and the beam the opened maze, and show the pick and the boon; Session never plays in the shared maze" lune run tests/run -- "$A/adapters.spec.luau" "$A/views.spec.luau"
check "AC7: in the classic maze three pickable walls are marked, a ghost pill turns the ghosts blue in its step, one seed plays the same; a ghost catches a picking player (caught), walks on while they stand and into holes; a blue ghost eaten mid-pick lets it finish; no one on a closed hole after a new run, and the holes still the ghosts' after a death" lune run tests/run -- "$A/classic.spec.luau" "$A/ghosts.spec.luau" "$A/eaten.spec.luau" "$A/closed.spec.luau"
check "AC8: the Picks feature exists, has unit specs, stays engine-free, and every dependency is declared" bash -c 'test -f src/shared/Logic/Picks/init.luau && test -d tests/unit/Picks && lune run tests/run -- tests/meta/architecture.spec.luau'
check "AC9: the key map and the camera keep the pins c0150 narrowed: the ten keys and the eye's Hop.rise at the shown tick" lune run tests/run -- tests/acceptance/f0104/keys.spec.luau tests/acceptance/f0101/place.spec.luau
check "AC10: game-design.md records the wall picks and the F key" bash -c 'grep -q "^## Wall picks (user, 2026-10-25; f0126)" .tracker/game-design.md && grep -qF "**F** picks a marked wall" .tracker/game-design.md'

finish
