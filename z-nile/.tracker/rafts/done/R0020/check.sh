#!/usr/bin/env bash
# Exit criteria for R0020. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(./zn members R0020); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ./zn promote-check R0020

claim_race_is_refused_end_to_end() {
  # the acceptance spec drives two terminals against a bare origin; running it again from the raft
  # level proves the whole path (new, claim, start) with the promoted or sequestered copy
  # wherever c0053 is (backlog, active/ during execution, done/), else the promoted copy (user-approved fix, PR #44)
  local A
  A="$(./zn find c0053 2>/dev/null)/acceptance"
  [[ -d $A ]] || A="tests/acceptance/c0053"
  lune run tests/run -- "$A/commands.spec.luau" >/dev/null 2>&1
}
check "RC1: two terminals cannot both claim or start the same item (end to end, bare origin)" claim_race_is_refused_end_to_end

stable_on_repeat() {
  local i A
  A="$(./zn find c0053 2>/dev/null)/acceptance"
  [[ -d $A ]] || A="tests/acceptance/c0053"
  for i in 1 2 3; do
    lune run tests/run -- "$A/publish.spec.luau" "$A/commands.spec.luau" >/dev/null 2>&1 || { echo "repeat $i failed"; return 1; }
  done
}
check "RC2: the publisher and command specs pass three times in a row (no leftover fixture state)" stable_on_repeat

finish
