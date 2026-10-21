#!/usr/bin/env bash
# Exit criteria for R0042. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0042); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0042

check "RC1: a design lesson is sourced from R0040's own design reviews" bash -c '[[ $(scripts/tracker.sh lessons --when design --full | grep -c "^sources: .*R0040 design-review-") -ge 1 ]]'
check "RC2: every design-review finding of R0040 and R0042 is harvested" scripts/tracker.sh lessons --uncovered R0040 R0042
check "RC3: the game and the architecture graph are untouched" git diff --quiet origin/main...HEAD -- src tracker/architecture.md

finish
