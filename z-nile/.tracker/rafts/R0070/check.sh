#!/usr/bin/env bash
# Exit criteria for R0070. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; the merger's `z-nile/check.sh --full` covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (full)" "$ZN_ROOT/z-nile/check.sh" --project z-nile --full
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0070); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0070

# sequestered specs: in each issue's folder before `done`, promoted to tests/acceptance/<id> after it
A89="$("$ZN_ROOT/zn" find c0189)/acceptance"; [[ -d $A89 ]] || A89="$PWD/tests/acceptance/c0189"
A94="$("$ZN_ROOT/zn" find c0194)/acceptance"; [[ -d $A94 ]] || A94="$PWD/tests/acceptance/c0194"
check "RC1: both members' pinned wording holds together in the shared skills" lune run tests/run -- "$A89/wiring.spec.luau" "$A94/docs.spec.luau"
check "RC2: ./zn hooks --check and ./zn tmp leftovers both run read-only" bash -c '"$ZN_ROOT/zn" hooks --check && "$ZN_ROOT/zn" tmp leftovers'

finish
