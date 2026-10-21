#!/usr/bin/env bash
# Acceptance checks for f0018. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0018 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0018"

check "AC1: Levels: the classic 21-level table, speeds and frightened time" lune run tests/run -- "$A/levels.spec.luau"
check "AC2: Game: the run's state machine, lives, extra life" lune run tests/run -- "$A/game.spec.luau"
check "AC3: a run through Session: countdown, discarded intents, death, game over, play again" lune run tests/run -- "$A/flow.spec.luau"
check "AC4: Session.frame is the snapshot plus a play record; the v1 snapshot is unchanged" lune run tests/run -- "$A/frame.spec.luau"
check "AC5: DEFAULT has no pauses, GAME_CONFIG is classic, bad speeds and rules refused" lune run tests/run -- "$A/config.spec.luau"
check "AC6: the server adapter uses GAME_CONFIG and sends frames" lune run tests/run -- "$A/adapter.spec.luau"

finish
