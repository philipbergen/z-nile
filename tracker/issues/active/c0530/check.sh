#!/usr/bin/env bash
# Acceptance checks for c0530 (emergent, written during R0090 execution).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh"
check "AC1: promote-check R0090 passes" scripts/tracker.sh promote-check R0090
check "AC2: the three edited specs still pass" lune run tests/run -- \
  tracker/issues/active/f0150/acceptance/eating.spec.luau \
  tracker/issues/active/f0170/acceptance/flow.spec.luau \
  tracker/issues/active/f0170/acceptance/game.spec.luau
finish
