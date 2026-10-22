#!/usr/bin/env bash
# Acceptance checks for c0056 (emergent, written during R0009 execution).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh"
# a spec of another issue: promoted to tests/acceptance/<id> after `done`, else in that issue's directory
spec() { # spec <issue> <name>
  if [[ -f tests/acceptance/$1/$2 ]]; then echo "tests/acceptance/$1/$2"; else echo "$(../zn find "$1")/acceptance/$2"; fi
}
check "AC1: promote-check R0009 passes" ../zn promote-check R0009
check "AC2: the three edited specs still pass" lune run tests/run -- \
  "$(spec f0016 eating.spec.luau)" "$(spec f0018 flow.spec.luau)" "$(spec f0018 game.spec.luau)"
finish
