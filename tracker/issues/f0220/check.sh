#!/usr/bin/env bash
# Acceptance checks for f0220. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0220 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0220"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: a normal ghost on the player's tile or swapping tiles with it kills, a blue one is eaten for 200, 400, 800, 1600, a revived ghost kills, eyes and ghosts in the house never touch the player" lune run tests/run -- "$A/contacts.spec.luau"
check "AC2: in a session the ghosts only move while the run is in play, a death sends everyone home, a kill beats an eating, the last pellet beats a kill, and the blue time ends with the run's power" lune run tests/run -- "$A/session-ghosts.spec.luau"
check "AC3: an idle player is caught 8 to 20 seconds of game time after play starts on every seed, deterministically" lune run tests/run -- "$A/idle-player.spec.luau"
existing_ac4_pass() { # the runner takes files, not directories
  local files
  files=$(find tests/acceptance/f0120 tests/acceptance/f0150 tests/acceptance/f0160 tests/acceptance/f0170 tests/acceptance/f0520 tests/unit/Session tests/scenario -name '*.spec.luau' | sort)
  # shellcheck disable=SC2086
  lune run tests/run -- $files
}
check "AC4: every existing session, game, pellet and client spec still passes (ghosts are off unless asked for)" existing_ac4_pass
check "AC5: the architecture rules hold (Logic is pure, every require declared in tracker/architecture.md, every feature has unit specs)" lune run tests/run -- tests/meta/architecture.spec.luau

finish
