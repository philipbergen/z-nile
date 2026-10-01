#!/usr/bin/env bash
# Exit criteria for R0090. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0090); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0090

# sequestered specs: in the issue directories before `tracker.sh done`, promoted to tests/acceptance after it
spec() { # spec <issue> <name>: path of that issue's acceptance spec, wherever it lives now
  local d
  d="$(git rev-parse --show-toplevel)"
  if [[ -f $d/tests/acceptance/$1/$2 ]]; then
    echo "$d/tests/acceptance/$1/$2"
  elif [[ -f $d/tracker/issues/active/$1/acceptance/$2 ]]; then # active: where `done` runs this check, before promotion
    echo "$d/tracker/issues/active/$1/acceptance/$2"
  else
    echo "$d/tracker/issues/$1/acceptance/$2"
  fi
}
check "RC1: a whole run plays headless: countdown, eating, power pellet, clear, next level, deaths, game over, play again" \
  lune run tests/run -- "$(spec f0160 full-run.spec.luau)"
check "RC2: the adapter sends Session.frame with GAME_CONFIG, and the v1 snapshot spec still passes" \
  lune run tests/run -- "$(spec f0170 adapter.spec.luau)" "$(spec f0120 snapshot.spec.luau)"

finish
