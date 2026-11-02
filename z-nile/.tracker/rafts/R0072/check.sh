#!/usr/bin/env bash
# Exit criteria for R0072. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; the merger's `z-nile/check.sh --full` covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (full)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --full
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0072); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0072

lessonlisted() { # $1 skill, $2 slug: the lesson is listed for both the design and the build steps (both are `when: both`)
  local w; for w in design build; do "$ZN_ROOT/zn" lessons --skill "$1" --when "$w" "$2" | grep -q "^- $1/$2 (" || { echo "$1/$2 is not listed for $w"; return 1; }; done
}
export -f lessonlisted
check "RC1: both new lessons are listed for the design and build steps and the ledgers read clean" bash -c '"$ZN_ROOT/zn" lessons --check && lessonlisted zz-review bound-every-probe && lessonlisted zz-arch scanning-loops-advance'

finish
