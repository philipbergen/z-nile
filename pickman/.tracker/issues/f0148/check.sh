#!/usr/bin/env bash
# Acceptance checks for f0148. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the project's home
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/f0148 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0148"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the best level's rules: the record and its reading, a start from 1 to the best, the best only rising (and written only then), the lobby's choice bounded by the best (no level, or one not allowed, is level 1), the claim once (else level 1), the picker shown from best 2 on and starting on the best, its arrows and its keys" lune run tests/run -- "$A/best.spec.luau"
check "AC2: a run joined on level n plays level n from its first step (the ramp's speeds, its ghosts, points times n, the extra life at 10,000 times n) and a new run starts there again; a start that is not a whole level of 1 or more is refused" lune run tests/run -- "$A/session.spec.luau"
check "AC3: the lobby's picker: START says START LEVEL n and sends n, redrawn on every change; Starts hands the kept level to the store hook before the teleport (a press that did not go leaves its level for the next that goes); LobbyPicker's arrows show from best 2, step by click, tap and the Left and Right keys (bound above the camera), sit either side of START and are touch-sized" lune run tests/run -- "$A/lobby.spec.luau"
check "AC4: the server adapters: the lobby puts the stored best on the player and stores the bounded choice; the game place claims the start once (level 1 when the store fails, cannot be opened or is silent for 10 s) and raises the best on a new level; Sessions makes each session on the level Sessions.starts gives, tells Sessions.made once it exists and its listeners every step; each Main wires them in order" lune run tests/run -- "$A/adapters.spec.luau"
check "AC5: game-design.md records the start level: the user's decisions, the prep's choices, the rows it changes" lune run tests/run -- "$A/docs.spec.luau"
check "AC6: the Best feature exists, has unit specs, stays engine-free, and every dependency is declared" bash -c 'test -f src/shared/Logic/Best/init.luau && test -d tests/unit/Best && lune run tests/run -- tests/meta/architecture.spec.luau'

finish
