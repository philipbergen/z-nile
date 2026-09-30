#!/usr/bin/env bash
# Exit criteria for R0020. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0020); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0020

# RC1: the raft's own plan runs on the real, migrated tracker and orders its issues as designed
# (c0420 layout, then c0041 worktrees, then c0430 plan): this ties the three issues together.
rc1_plan() {
  local out; out=$(scripts/tracker.sh workstreams R0020) || return 1
  echo "$out"
  grep -qE "^c0420 wave 1$" <<<"$out" && grep -qE "^c0041 wave 2 after c0420" <<<"$out" \
    && grep -qE "^c0430 wave 3 after " <<<"$out"
}
check "RC1: workstreams plans R0020 as c0420 (wave 1), c0041 (wave 2), c0430 (wave 3)" rc1_plan

finish
