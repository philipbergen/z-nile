#!/usr/bin/env bash
# Exit criteria for R0010. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0010); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC1: the place tier runs with at least one passing spec file" bash -c \
  'out=$(lune run tests/run -- $(find tests/place -name "*.spec.luau" | sort)) && echo "$out" && echo "$out" | grep -Eq "^[0-9]+ passed, 0 failed, [1-9][0-9]* spec files$"'

finish
