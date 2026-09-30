#!/usr/bin/env bash
# Acceptance checks for c0410. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0410 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0410"

check "AC1: review findings are second-order and still parse for tracker.sh done" lune run tests/run -- "$A/format.spec.luau"
check "AC2: the issue template has a Rules and mutants table" lune run tests/run -- "$A/table.spec.luau"
check "AC3: review: one step further (prose), design-mode item 0 audits Rules and mutants, code mode escalates" \
  lune run tests/run -- "$A/review-skill.spec.luau"
check "AC4: ticket-prep: step 3 asks for the Rules and mutants table, step 5 runs the consequence step" \
  lune run tests/run -- "$A/ticket-prep.spec.luau"
check "AC5: tracker.sh metrics reports review rounds per raft" lune run tests/run -- "$A/rounds.spec.luau"

finish
