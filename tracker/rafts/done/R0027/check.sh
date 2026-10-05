#!/usr/bin/env bash
# Exit criteria for R0027. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0027); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0027

check "RC1: the real tracker tree passes tracker.sh audit" scripts/tracker.sh audit
check "RC2: tracker.sh list succeeds on the real tracker tree" scripts/tracker.sh list
check "RC3: the real tracker/next is above every number in use" \
  bash -c '! scripts/tracker.sh audit | grep -q "next-behind"'

finish
