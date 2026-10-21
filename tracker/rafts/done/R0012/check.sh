#!/usr/bin/env bash
# Exit criteria for R0012. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0012); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0012

# sequestered specs: in the issue directories before `tracker.sh done`, promoted to tests/acceptance after it
spec() { # spec <issue> <name>: path of that issue's acceptance spec, wherever it lives now
  local d
  d="$(git rev-parse --show-toplevel)"
  [[ -f $d/tests/acceptance/$1/$2 ]] && echo "$d/tests/acceptance/$1/$2" || echo "$d/$(scripts/tracker.sh find "$1")/acceptance/$2"
}
check "RC1: a phone-sized session swipes to turn, drags to look, taps snap, and the HUD stays readable" \
  lune run tests/run -- "$(spec f0029 phone.spec.luau)"
check "RC2: keyboard, mouse, the four intents, the zero-inset HUD and the desktop radar stay as they are" \
  lune run tests/run -- tests/acceptance/f0014/place.spec.luau tests/acceptance/f0014/look.spec.luau \
  tests/acceptance/f0014/keys.spec.luau tests/acceptance/f0019/layout.spec.luau \
  tests/acceptance/f0019/place.spec.luau tests/acceptance/f0012/config.spec.luau \
  tests/acceptance/f0031/place.spec.luau tests/acceptance/f0033/adapters.spec.luau \
  tests/acceptance/f0054/adapters.spec.luau tests/acceptance/d0105/radar.spec.luau \
  tests/acceptance/d0105/adapter.spec.luau tests/unit/Hud/hud.spec.luau tests/unit/View/view.spec.luau

finish
