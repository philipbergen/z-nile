#!/usr/bin/env bash
# Acceptance checks for f0031. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0031 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0031"

check "AC1: Flow.overlay: READY!, the dying fade, the level-clear flash and the GAME OVER results (narrowed by c0063)" lune run tests/run -- "$A/overlay.spec.luau"
check "AC2: the server stays thin: any Session.playAgain call is the sender's own, and no phase is read (narrowed by c0063)" lune run tests/run -- "$A/adapter.spec.luau"
check "AC3: the client presents the flow through FlowView, MazeView.flash and Camera.setCursor" lune run tests/run -- "$A/place.spec.luau"
check "AC4: a whole run on screen: countdown, score, flash, next level, deaths, the game-over results, a new run from Logic (narrowed by c0063)" lune run tests/run -- "$A/presentation-run.spec.luau"
check "AC5: Flow is a declared feature with unit specs, and Logic stays pure" \
  bash -c 'test -f src/shared/Logic/Flow/init.luau && ls tests/unit/Flow/*.spec.luau && lune run tests/run -- tests/meta/architecture.spec.luau'

finish
