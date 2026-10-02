#!/usr/bin/env bash
# Exit criteria for R0200. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0200); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0200

claim_race_is_refused_end_to_end() {
  # the acceptance spec drives two terminals against a bare origin; running it again from the raft
  # level proves the whole path (new, claim, start) with the promoted or sequestered copy
  local A="tracker/issues/c0510/acceptance"
  [[ -d $A ]] || A="tests/acceptance/c0510"
  lune run tests/run -- "$A/commands.spec.luau" >/dev/null 2>&1
}
check "RC1: two terminals cannot both claim or start the same item (end to end, bare origin)" claim_race_is_refused_end_to_end

stable_on_repeat() {
  local i A="tracker/issues/c0510/acceptance"
  [[ -d $A ]] || A="tests/acceptance/c0510"
  for i in 1 2 3; do
    lune run tests/run -- "$A/publish.spec.luau" "$A/commands.spec.luau" >/dev/null 2>&1 || { echo "repeat $i failed"; return 1; }
  done
}
check "RC2: the publisher and command specs pass three times in a row (no leftover fixture state)" stable_on_repeat

finish
