#!/usr/bin/env bash
# Exit criteria for R0140. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0140); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0140

check "RC1: scripts/setup.sh is valid shell" bash -n scripts/setup.sh
check "RC2: the board builds into a fresh directory with the workflow's command" bash -c 'out=$(mktemp -d)/dist/board.html && scripts/tracker.sh board --out "$out" >/dev/null && grep -q "board-data" "$out"'

finish
