#!/usr/bin/env bash
# Acceptance checks for f0234. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0234 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0234"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: Hop.held is the top of a hop until half a hop before play, then an ordinary hop's descent that lands when play starts, 0 after it, steady and falling, and 0 for a nil or non-finite input" lune run tests/run -- "$A/held.spec.luau"
check "AC2: View.readyEnd names a ready frame's tick plus timer and keeps the last answer otherwise; over a real run it names the first tick in play of the run's start, a new life, a new level and a new run, and no frame of a pause carries a hop" lune run tests/run -- "$A/ready.spec.luau"
check "AC3: the real Camera on a stub engine, fed a real run's frames as Main feeds them, holds the eye at the top of a hop through the run's and a new life's READY pause, lands as the first step in play is shown, keeps the stick, arrow-key and mouse look live there, still lifts a hop in play, and follows the clock, not the frame rate" lune run tests/run -- "$A/camera.spec.luau"
check "AC4: Main hands Camera.ready(frame.play, frame.tick); the camera folds it by View.readyEnd, holds by Hop.held and sends nothing; game-design.md and architecture.md record it" lune run tests/run -- "$A/place.spec.luau"
check "AC5: the existing hop's camera pins still hold (f0101's eye and shown tick, f0126's hop length)" bash -c 'lune run tests/run -- tests/acceptance/f0101/place.spec.luau tests/acceptance/f0126/adapters.spec.luau'
check "AC6: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau

finish
