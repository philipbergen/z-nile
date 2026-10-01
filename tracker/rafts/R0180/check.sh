#!/usr/bin/env bash
# Exit criteria for R0180. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0180); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0180

check "RC1: runtime tests still skip green when publishing is not configured" bash -c 'set -o pipefail; out=$(env -u ROBLOX_API_KEY -u ROBLOX_BETA_UNIVERSE_ID -u ROBLOX_BETA_PLACE_ID -u OPENCLOUD_BASE lune run scripts/runtime-test -- 1 2>&1) && grep -q "not configured" <<<"$out"'

finish
