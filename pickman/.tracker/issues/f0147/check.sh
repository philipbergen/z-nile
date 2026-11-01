#!/usr/bin/env bash
# Acceptance checks for f0147. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the project's home
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0147 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0147"

# another item's acceptance spec, wherever it lives now: promoted under tests/acceptance once that item is done,
# else in its issue folder (`./zn find` prints it from the home ac.sh cds to, so it is used under $PWD as it is)
spec() { # spec <item> <file>
  local promoted="$PWD/tests/acceptance/$1/$2"
  if [[ -f $promoted ]]; then echo "$promoted"; else echo "$PWD/$(../zn find "$1")/acceptance/$2"; fi
}

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the ramp: ten picks a level, level 1 at 70% of the classic level 1 for the player and every ghost, each level 5% faster up to level 34 (the player and the hunting ghosts in whole units, strictly; the tunnel and frightened ghosts at the exact rate, carrying the fraction) and level 34's speeds after it, the eyes on the ramp but never past a tile, level 1's frightened time, flashes, timetable and house limits on every level (in Levels and in a ghost set), the classic tables untouched, a bad ramp refused, and the shipped session's ghosts moving the ramp's units" lune run tests/run -- "$A/ramp.spec.luau"
check "AC2: in a ramped session the tenth finished pick ends the level and the pellets never do (an emptied maze stays empty); the next level is a fresh maze with its count at 0; a death keeps the count; the player and the pick run the level's ramped speeds; without a ramp the last pellet still clears a level; the tenth pick's bonanza (a banked faster pick and a shot at once, no rolled boon; on the next level long hops all level and a long ghost pill when play starts after READY); every point on level n is worth n times, and the extra life comes at 10,000 times the starting level" lune run tests/run -- "$A/levels.spec.luau"
check "AC3: the HUD shows PICKS n/10 from the frame in the row under the score, clear of every other block, both radars, the touch buttons, the pick bar and the banner on every sample screen, and HudView draws and hides it; the power bar follows the frame's own period; the tenth pick's banner says BONANZA!" lune run tests/run -- "$A/hud.spec.luau"
check "AC4: game-design.md records levels by picked walls: the user's decisions, the prep's choices marked (prep), and the restated rules that changed" lune run tests/run -- "$A/docs.spec.luau"
check "AC5: the narrowed promoted specs pass: the four c0176 narrows on the shipped config less its ramp (f0023's session ghosts, f0100's drops and shots, f0101's airborne player), and f0125's speeds, narrowed by c0177, on the ramp" lune run tests/run -- tests/acceptance/f0023/session-ghosts.spec.luau tests/acceptance/f0100/drops.spec.luau tests/acceptance/f0100/shots.spec.luau tests/acceptance/f0101/airborne.spec.luau "$(spec f0125 speeds.spec.luau)"
check "AC6: every feature stays engine-free and every dependency is declared (no new edge)" lune run tests/run -- tests/meta/architecture.spec.luau

finish
