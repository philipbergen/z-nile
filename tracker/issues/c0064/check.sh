#!/usr/bin/env bash
# Acceptance checks for c0064. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0064 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0064"

check "AC1: the publish plan: legacy without the game place's id, two places with it, bad ids refused" lune run tests/run -- "$A/plan.spec.luau"
check "AC2: the project copy points at the checkout from anywhere and differs only in the injected ids" lune run tests/run -- "$A/project.spec.luau"
check "AC3: deploy-beta builds both places, then publishes the game, then the lobby told its id" lune run tests/run -- "$A/deploy.spec.luau"
check "AC4: runtime tests per place: lobby scripts pass only in the injected lobby; runtime-test --lobby" lune run tests/run -- "$A/runtime.spec.luau"
check "AC5: the beta job: game place variable, the lobby's runtime step, the secret in three steps" lune run tests/run -- "$A/workflow.spec.luau"
check "AC6: SETUP.md and the testing skill document two places and the owner's steps" lune run tests/run -- "$A/docs.spec.luau"
check "AC7: the promoted Beta specs, narrowed in this raft, still pass" lune run tests/run -- tests/acceptance/c0015/workflow.spec.luau tests/acceptance/c0003/pipeline.spec.luau tests/acceptance/c0015/deploy-e2e.spec.luau tests/acceptance/c0015/deploy-cli.spec.luau tests/acceptance/c0003/runner.spec.luau tests/acceptance/c0003/runner-e2e.spec.luau tests/acceptance/c0003/scripts.spec.luau
check "AC8: the checked-in lobby still says GamePlaceId 0 (never a real id in the repo)" lune run tests/run -- tests/acceptance/f0061/lobby-place.spec.luau

finish
