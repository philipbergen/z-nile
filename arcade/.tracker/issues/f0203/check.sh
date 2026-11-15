#!/usr/bin/env bash
# Acceptance checks for f0203. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0203 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0203"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: Rng draws a seeded, plain-data sequence; a stream picks it, exactly" lune run tests/run -- "$A/rng.spec.luau"
check "AC2: Pad folds the stick into directions with hysteresis, looks at a rate, and tracks the driving gamepad" lune run tests/run -- "$A/pad.spec.luau"
check "AC3: Touch folds fingers into button presses and releases, swipes and look steps, one finger a zone" lune run tests/run -- "$A/touch.spec.luau"
check "AC4: Look turns, springs, eases and blends the first-person look, frame-rate independent" lune run tests/run -- "$A/look.spec.luau"
check "AC5: every feature of every game's design is built from the cores on keyboard, gamepad and touch, the open cells are listed and servable, and the cores hold no key map" lune run tests/run -- "$A/games.spec.luau"
check "AC6: the four features keep the library's structural rules (strict, engine-free leaves with unit specs)" lune run tests/run -- tests/meta/architecture.spec.luau
check "AC7: the library place holds the four cores as ModuleScripts under ReplicatedStorage.Arcade.Logic, and its requires resolve" lune run tests/run -- "$A/place.spec.luau" tests/place/library.spec.luau
check "AC8: the library's architecture states the every-input rule, the open cells and the differences from pickman, before the deps block" lune run tests/run -- "$A/docs.spec.luau"
finish
