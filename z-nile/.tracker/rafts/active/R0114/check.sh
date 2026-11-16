#!/usr/bin/env bash
# Exit criteria for R0114. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; a game pull request's merger runs `z-nile/check.sh --full`, which covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --affected
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0114); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0114

check "RC1: none of c0348's promoted specs is in the slow tier, so a gate runs the guards this raft adds" bash -c '! grep -F "acceptance/c0348/" tests/slow.tsv'

finish
