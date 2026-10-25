#!/usr/bin/env bash
# Exit criteria for R0044. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0044); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0044

check "RC1: c0128, which narrows the promoted hiscore adapter specs this raft overrides, is done" bash -c '[[ "$(scripts/tracker.sh find c0128)" == tracker/issues/done/c0128 ]]'

finish
