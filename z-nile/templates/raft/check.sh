#!/usr/bin/env bash
# Exit criteria for {{ID}}. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/ for pickman's, the root for z-nile's); $ZN_ROOT is the root
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" "$ZN_ROOT/z-nile/check.sh" --full
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members {{ID}}); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check {{ID}}

# check "RC1: <end-to-end statement>" <command>

finish
