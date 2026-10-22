#!/usr/bin/env bash
# Exit criteria for R0015. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(./zn members R0015); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ./zn promote-check R0015

# sequestered specs: in the issue directories before `./zn done`, promoted to tests/acceptance after it
spec() { # spec <issue> <name>: path of that issue's acceptance spec, wherever it lives now
  local d
  d="$(git rev-parse --show-toplevel)"
  [[ -f $d/tests/acceptance/$1/$2 ]] && echo "$d/tests/acceptance/$1/$2" || echo "$d/$(./zn find "$1")/acceptance/$2"
}
check "RC1: a whole run on screen: HUD, overlay and pellets from every frame, countdown to play again" \
  lune run tests/run -- "$(spec f0031 presentation-run.spec.luau)"
check "RC2: the earlier adapter contracts still hold: remotes, frames, step rate, client boot" \
  lune run tests/run -- tests/acceptance/f0013/place.spec.luau tests/acceptance/f0014/place.spec.luau \
  tests/acceptance/f0018/adapter.spec.luau tests/acceptance/f0054/adapters.spec.luau tests/acceptance/f0018/frame.spec.luau

finish
