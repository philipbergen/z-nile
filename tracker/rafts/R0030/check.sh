#!/usr/bin/env bash
# Exit criteria for R0030. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0030); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0030

# RC1: the scenario tier exists, uses the harness, and is green. An empty or missing tier fails.
check "RC1: tests/scenario has harness-driven specs and they pass" bash -c '
  files=$(find tests/scenario -name "*.spec.luau" 2>/dev/null | sort)
  [ -n "$files" ] || { echo "no specs in tests/scenario"; exit 1; }
  grep -l "@tests/lib/sim" $files >/dev/null || { echo "no scenario spec requires @tests/lib/sim"; exit 1; }
  lune run tests/run -- $files'
# RC2: simulations (including failing ones that write replays) never dirty the working tree.
check "RC2: sim specs leave git status unchanged" bash -c '
  before=$(git status --porcelain)
  # the c0090 acceptance specs live under tracker/ before `done` and tests/acceptance/c0090/ after
  files=$(find tests/scenario tracker/issues tests/acceptance -name "*.spec.luau" \( -path "*c0090*" -o -path "tests/scenario/*" \) 2>/dev/null | sort)
  [ -n "$files" ] || { echo "no sim specs found"; exit 1; }
  lune run tests/run -- $files >/dev/null
  after=$(git status --porcelain)
  [ "$before" = "$after" ] || { echo "tree changed:"; diff <(echo "$before") <(echo "$after"); exit 1; }'

finish
