#!/usr/bin/env bash
# Acceptance checks for f0199. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0199 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0199"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: arcade's Logic/Travel keeps pickman's Travel rules exactly: the place-id check, one request at a time with a ticket, the 15 s timeout after the engine call returns, the 60 s cap, the 3 s cool-down, late and older reports ignored, players separate, the config it is given" lune run tests/run -- "$A/travel.spec.luau"
check "AC2: Places.read reads PortalPlaceId, PickmanPlaceId, SnakePlaceId, InvadersPlaceId and AsteroidsPlaceId once each through the read it is given, and answers a fresh frozen table of the published ids, each value through the place-id check, 0 or anything not a place id meaning not published" lune run tests/run -- "$A/places.spec.luau"
check "AC3: in the built library place Travel is the ModuleScript ReplicatedStorage.Arcade.Logic.Travel and Places is ReplicatedStorage.Arcade.Places, each reached by @game/ReplicatedStorage/Arcade/..., holding its source; Travel is a leaf that requires nothing and names no place, and Places requires only Travel" lune run tests/run -- "$A/place.spec.luau"

finish
