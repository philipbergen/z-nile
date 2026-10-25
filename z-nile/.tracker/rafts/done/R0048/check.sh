#!/usr/bin/env bash
# Exit criteria for R0048. SEQUESTERED: never edit during execution.
# Runs the full gate (both projects: c0120 moves pickman and the tooling), every member issue's check.sh, then the
# promotion check. ac.sh runs this from the raft's project home (z-nile/) once c0120's move is in; $ZN_ROOT is the
# repository root.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" "$ZN_ROOT/z-nile/check.sh" --full
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0048); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0048

finish
