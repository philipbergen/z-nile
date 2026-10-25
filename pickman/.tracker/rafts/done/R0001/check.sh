#!/usr/bin/env bash
# Exit criteria for R0001. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" ../z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(../zn members R0001); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC1: the place tier runs with at least one passing spec file" bash -c \
  'files=$(find tests/place -name "*.spec.luau" 2>/dev/null | sort); [[ -n $files ]] && out=$(lune run tests/run -- $files) && echo "$out" && echo "$out" | grep -Eq "^[1-9][0-9]* passed, 0 failed, [1-9][0-9]* spec files$"'

check "RC2: acceptance specs will survive promotion into tests/ (type check + meta)" ../zn promote-check R0001

finish
