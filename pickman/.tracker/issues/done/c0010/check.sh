#!/usr/bin/env bash
# Acceptance checks for c0010. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0010 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0010"

check "AC1: script delivery, tick semantics and trace queries" lune run tests/run -- "$A/script.spec.luau"
check "AC2: expectations, stopWhen and failure reporting" lune run tests/run -- "$A/expect.spec.luau"
check "AC3: failures write a replay that sim.replay reproduces" lune run tests/run -- "$A/replay.spec.luau"
check "AC4: per-seed reproducibility and assertDeterministic" lune run tests/run -- "$A/determinism.spec.luau"
check "AC5: harness misuse fails before any step" lune run tests/run -- "$A/misuse.spec.luau"
check "AC6: bench interleaves worlds within the budget" lune run tests/run -- "$A/bench.spec.luau"
check "AC7: testing skill documents tests/scenario and the sim harness" \
  bash -c 'f=.claude/skills/testing/SKILL.md; for s in "tests/scenario/" "@tests/lib/sim" "sim.replay" "Step k moves the world from time k to time k+1" "Events returned by step k are visible at time k+1" "An intent at k is delivered in step k" "timing exception" "tests/integration/ is for"; do grep -qF "$s" "$f" || { echo "missing: $s"; exit 1; }; done'

finish
