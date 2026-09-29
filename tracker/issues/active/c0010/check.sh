#!/usr/bin/env bash
# Acceptance checks for c0010. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance" # sequestered specs; see the testing skill
source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "AC1: tracker lifecycle spec passes" lune run tests/run -- "$A/tracker-lifecycle.spec.luau"
check "AC2: CI bootstraps via setup.sh, is dispatchable, skips only drafts" lune run tests/run -- "$A/ci-workflow.spec.luau"
check "AC3: CI green for this branch's exact HEAD" bash -c 'scripts/ci-verify.sh &&
  n=$(gh run list --workflow check.yml --commit "$(git rev-parse HEAD)" --event workflow_dispatch \
    --json conclusion -q "[.[] | select(.conclusion == \"success\")] | length") && [[ $n -ge 1 ]]'
check "AC4: setup.sh is idempotent on a set-up host" scripts/setup.sh
check "AC5: this branch has an open PR" bash -c '[[ $(gh pr view --json state -q .state) == OPEN ]]'

finish
