#!/usr/bin/env bash
# Acceptance checks for d0149. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0149 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0149"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: in Touch's fold the steer circle's pull turns once a push as the keys, the look circle points the view once a finger is a pull (12 px, or still undecided when its own tap timer fires) and a short tap only hops, on the lift, FIRE and PICK act on the press, nothing elsewhere, one finger a control; Touch.buttons places the 30% circles and the buttons" lune run tests/run -- "$A/fold.spec.luau"
check "AC2: on every sample screen the circles and buttons are at least 44 px, inside the safe rectangle, and clear of each other, the HUD, the radar, the pick bar, the banner and the danger ring (but PICK on the one screen the user accepted)" lune run tests/run -- "$A/clear.spec.luau"
check "AC3: Controls sends the steer turns, the boost on two quick pulls up, the tap's hop, FIRE's shot and PICK's pick, points the camera (a held thumb by its timer, by finger id) and lets every finger go when the controls move; Camera looks and aims by the point; HudView draws the circles, knobs, FIRE and PICK on touch only, no snap or JUMP; Main wires them" lune run tests/run -- "$A/adapters.spec.luau"
check "AC4: the look circle's point rides in View's arrows: the look turns to it at the arrows' rate, level, aims by it, springs back when let go, and held arrows win" lune run tests/run -- "$A/look.spec.luau"
check "AC5: game-design.md describes the circles and nowhere offers the swipes, drag look, snap button or JUMP, and architecture.md declares Touch -> Pad without Touch -> Hud or View" env D0149_EXACT=1 lune run tests/run -- "$A/docs.spec.luau"
check "AC6: the replaced touch specs are narrowed (c0182) and the rest of the touch, key, HUD, blaster and hop specs still pass" bash -c 'shopt -s nullglob; files=(tests/acceptance/f0027/*.spec.luau tests/acceptance/f0028/*.spec.luau tests/acceptance/f0029/*.spec.luau tests/acceptance/f0100/*.spec.luau tests/acceptance/f0101/*.spec.luau tests/acceptance/f0104/*.spec.luau tests/acceptance/f0110/*.spec.luau tests/unit/Touch/*.spec.luau tests/unit/View/*.spec.luau tests/place/touch-adapters.spec.luau tests/place/hud-shots.spec.luau); ((${#files[@]} >= 20)) || { echo "only ${#files[@]} spec files found" >&2; exit 1; }; lune run tests/run -- "${files[@]}"'
check "AC7: Logic stays engine-free and every dependency is declared" lune run tests/run -- tests/meta/architecture.spec.luau
check "AC8: the wall picks (f0126), the boost (f0143), the danger ring (f0158) and c0155's narrowed pins still pass their own checks, as c0182 narrowed them" bash -c '"$ZN_ROOT/zn" check f0126 && "$ZN_ROOT/zn" check f0143 && "$ZN_ROOT/zn" check f0158 && "$ZN_ROOT/zn" check c0155'

finish
