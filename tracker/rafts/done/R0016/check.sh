#!/usr/bin/env bash
# Exit criteria for R0016. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0016); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0016

check "RC1: the board workflow's setup step is the tools-only mode" grep -q -F "run: scripts/setup.sh --tools" .github/workflows/board.yml
check "RC2: the board builds into a fresh directory with the workflow's command" bash -c 'out=$(mktemp -d)/dist/board.html && scripts/tracker.sh board --out "$out" >/dev/null && grep -q "board-data" "$out"'
check "RC3: the lifecycle spec that drives tracker.sh start still passes" lune run tests/run -- tests/acceptance/c0001/tracker-lifecycle.spec.luau

finish
