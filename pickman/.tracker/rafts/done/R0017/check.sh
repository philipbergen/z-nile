#!/usr/bin/env bash
# Exit criteria for R0017. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0017); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0017

# the specs live in the issue directory before `tracker.sh done`, promoted to tests/acceptance after it
spec() {
  local d
  d="$(git rev-parse --show-toplevel)"
  [[ -f $d/tests/acceptance/f0054/$1 ]] && echo "$d/tests/acceptance/f0054/$1" || echo "$d/$(scripts/tracker.sh find f0054)/acceptance/$1"
}
check "RC1: end to end, the player covers 3.75 tiles in one real second through the server's own clock" \
  lune run tests/run -- "$(spec speed.spec.luau)"

finish
