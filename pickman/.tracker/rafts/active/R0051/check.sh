#!/usr/bin/env bash
# Exit criteria for R0051. SEQUESTERED: never edit during execution.
# Runs the raft's project gate, every member issue's check.sh, then raft-level end-to-end checks.
# ac.sh runs this from the raft's project home (pickman/, z-nile/); $ZN_ROOT is the repository root. The project's gate
# proves that project alone; CI's job per project covers the others (c0120).
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: project gate passes (full)" "$ZN_ROOT/z-nile/check.sh" --project pickman --full
# every issue naming this raft, including emergent ones
for dir in $("$ZN_ROOT/zn" members R0051); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" "$ZN_ROOT/zn" promote-check R0051

F0110="$("$ZN_ROOT/zn" find f0110)"
F0110_SPECS="$ZN_ROOT/$F0110/acceptance"
[[ -d $F0110_SPECS ]] || F0110_SPECS="$PWD/tests/acceptance/f0110"
check "RC1: a touch ghost hunt end to end: a fire tap eats the ghost the look points at, and a hop tap hops" lune run tests/run -- "$F0110_SPECS/hunt.spec.luau"

finish
