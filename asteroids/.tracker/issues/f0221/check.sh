#!/usr/bin/env bash
# Acceptance checks for f0221. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0221 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0221"
# f0220's solo specs, wherever they are now: promoted under tests/acceptance/f0220, or still in its item's folder
S="$PWD/tests/acceptance/f0220"
[[ -d $S ]] || S="$ZN_ROOT/$(cd "$ZN_ROOT" && ./zn find f0220)/acceptance"
SOLO=("$S"/field.spec.luau "$S"/game.spec.luau "$S"/hyperspace.spec.luau "$S"/lives.spec.luau "$S"/rocks.spec.luau
  "$S"/saucers.spec.luau "$S"/ship.spec.luau "$S"/shots.spec.luau "$S"/waves.spec.luau)

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: two ships share one field from opposite sides, with the solo waves at 1.5 x the rocks, clear of both ships" lune run tests/run -- "$A/field.spec.luau"
check "AC2: each player has their own ship, shots, score, lives and extra lives on the shared rocks; the saucer fires at the nearer ship" lune run tests/run -- "$A/scores.spec.luau"
check "AC3: by default shots pass through the other ship and the ships bounce off each other; each is one switch" lune run tests/run -- "$A/contact.spec.luau"
check "AC4: a lone survivor plays on; the match ends when both are out; each player revives on their own, or leaves" lune run tests/run -- "$A/survivor.spec.luau"
check "AC5: a seeded, deterministic, JSON-safe match at 60 ticks a second whose players' events carry their slot" lune run tests/run -- "$A/match.spec.luau"
check "AC6: the solo rules are unchanged: f0220's acceptance specs pass on the shared steps" lune run tests/run -- "${SOLO[@]}"
check "AC7: every Logic feature is engine-free, requires only declared edges and has unit specs" lune run tests/run -- tests/meta/architecture.spec.luau

finish
