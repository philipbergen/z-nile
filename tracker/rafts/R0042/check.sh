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

check "RC1: the game and the architecture graph are untouched" git diff --quiet origin/main...HEAD -- src tracker/architecture.md

TAB="tracker/issues/c0118/acceptance/tab.spec.luau"
[[ -f $TAB ]] || TAB="tracker/issues/active/c0118/acceptance/tab.spec.luau"
[[ -f $TAB ]] || TAB="tests/acceptance/c0118/tab.spec.luau"
check "RC2: a z-nile issue is only on that tab" lune run tests/run -- "$TAB"

finish
