#!/usr/bin/env bash
# Acceptance checks for c0010. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0010 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0010"

check "AC1: tracker lifecycle spec passes" lune run tests/run -- "$A/tracker-lifecycle.spec.luau"
check "AC2: CI bootstraps via setup.sh, is dispatchable, skips only drafts" lune run tests/run -- "$A/ci-workflow.spec.luau"
check "AC3: CI green for this branch's exact HEAD" bash -c 'scripts/ci-verify.sh &&
  n=$(gh run list --workflow check.yml --commit "$(git rev-parse HEAD)" --event workflow_dispatch \
    --json conclusion -q "[.[] | select(.conclusion == \"success\")] | length") && [[ $n -ge 1 ]]'
check "AC4: setup.sh is idempotent on a set-up host" scripts/setup.sh
check "AC5: this branch has an open PR" bash -c '[[ $(gh pr view --json state -q .state) == OPEN ]]'

finish
