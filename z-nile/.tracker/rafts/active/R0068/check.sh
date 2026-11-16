#!/usr/bin/env bash
# Exit criteria for R0068. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; the merger's `z-nile/check.sh --full` covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (full)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --full
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0068); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0068

check "RC1: lessons and harvest ledgers of the whole tree pass the new step rules" "$ZN_ROOT/zn" lessons --check
check "RC2: the raft's own harvest entries all name the step that erred" "$ZN_ROOT/zn" lessons --unattributed R0068

finish
