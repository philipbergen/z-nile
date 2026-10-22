#!/usr/bin/env bash
# Acceptance checks for c0127. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0127 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0127"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: the reused-pid rule (start ids compared for equality), and startOf gives the same id per process wherever specs run, nil for a non-pid or an exited one" lune run tests/run -- "$A/rules.spec.luau"
check "AC2: runs record start ids; a lock held only by pids with a different recorded id is taken over; a matching, missing or unreadable id holds; only live pids are read" lune run tests/run -- "$A/reuse.spec.luau"
check "AC3: the testing skill's Lock bullet states the start-id rule and that an unreadable id still holds" lune run tests/run -- "$A/skill.spec.luau"
check "AC4: the full gate passes" scripts/check.sh --full
check "AC5: on Linux CI, the acceptance specs (sequestered or promoted) pass for this branch's exact, pushed HEAD" bash -c 'scripts/ci-verify.sh &&
  n=$(gh run list --workflow check.yml --commit "$(git rev-parse HEAD)" --event workflow_dispatch \
    --json conclusion -q "[.[] | select(.conclusion == \"success\")] | length") && [[ $n -ge 1 ]]'

finish
