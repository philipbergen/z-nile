#!/usr/bin/env bash
# Exit criteria for R0009. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" ../z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(../zn members R0009); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ../zn promote-check R0009

# sequestered specs: in the issue directories before `./zn done`, promoted to tests/acceptance after it
spec() { # spec <issue> <name>: path of that issue's acceptance spec, wherever it lives now
  local d
  d="$(git rev-parse --show-toplevel)"
  [[ -f $d/tests/acceptance/$1/$2 ]] && echo "$d/tests/acceptance/$1/$2" || echo "$d/$(../zn find "$1")/acceptance/$2"
}
check "RC1: a whole run plays headless: countdown, eating, power pellet, clear, next level, deaths, game over, play again" \
  lune run tests/run -- "$(spec f0017 full-run.spec.luau)"
check "RC2: the adapter sends Session.frame with GAME_CONFIG, and the v1 snapshot spec still passes" \
  lune run tests/run -- "$(spec f0018 adapter.spec.luau)" "$(spec f0013 snapshot.spec.luau)"

finish
