#!/usr/bin/env bash
# Exit criteria for R0090. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; the merger's `z-nile/check.sh --full` covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (affected)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --affected
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0090); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0090

# RC1: the grouping with c0264 was split (its AC8 diffs the README outside two sections against the pre-raft main)
not_member() { ! "$ZN_ROOT/zn" members R0090 | grep -q c0264; }
check "RC1: c0264 is not a member of R0090 (its README check cannot hold inside this PR)" not_member
# RC2: the cross-raft order is written in both rafts (R0090 here, R0092 for c0264), with the merge as the trigger
order_in() { local f; f="$("$ZN_ROOT/zn" find "$1")/$1.md"; grep -q "merged before" "$f" && grep -q "$2" "$f"; }
order_both() { order_in R0090 R0092 && order_in R0092 R0090; }
check "RC2: R0090 and R0092 each name the other and the merge as the trigger" order_both
# RC3: the c0261 text the handoff to c0260 copies is still in c0261's design
idea_activity() { grep -q "zz-review-idea" "$("$ZN_ROOT/zn" find c0261)/c0261.md"; }
check "RC3: c0261 still derives the idea review's activity as zz-review-idea in FINAL_REVIEWS" idea_activity

finish
