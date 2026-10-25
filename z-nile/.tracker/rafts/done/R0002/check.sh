#!/usr/bin/env bash
# Exit criteria for R0002. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" ./check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(../zn members R0002); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ../zn promote-check R0002

# RC1: the raft's own plan runs on the real, migrated tracker and orders its issues as designed
# (c0044 layout, then c0005 worktrees, then c0046 launch, then c0045 plan): this ties the issues together.
rc1_plan() {
  local out; out=$(../zn workstreams R0002) || return 1
  echo "$out"
  grep -qE "^c0044 wave 1$" <<<"$out" && grep -qE "^c0005 wave 2 after c0044" <<<"$out" \
    && grep -qE "^c0046 wave 3 after " <<<"$out" && grep -qE "^c0045 wave 4 after " <<<"$out"
}
check "RC1: workstreams plans R0002 as c0044, c0005, c0046, c0045 (waves 1 to 4)" rc1_plan

finish
