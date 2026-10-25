#!/usr/bin/env bash
# Exit criteria for R0042. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" ./check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(../zn members R0042); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ../zn promote-check R0042

check "RC1: a design lesson is sourced from R0040's own design reviews" bash -c '[[ $(../zn lessons --when design --full | grep -c "^sources: .*R0040 design-review-") -ge 1 ]]'
check "RC2: every design-review finding of R0040 and R0042 is harvested" ../zn lessons --uncovered R0040 R0042
check "RC3: the game and the architecture graph are untouched" git diff --quiet origin/main...HEAD -- src ../pickman/.tracker/architecture.md

finish
