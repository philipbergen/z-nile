#!/usr/bin/env bash
# Acceptance checks for c0003. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0003 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0003"

check "AC1: OpenCloud.execute: creates a task on the published version, waits, reports results, failures and timeouts" lune run tests/run -- "$A/execute.spec.luau"
check "AC2: OpenCloud.runSuite: a script passes only by returning PASS; one failure doesn't stop the rest" lune run tests/run -- "$A/suite.spec.luau"
check "AC3: scripts/runtime-test: usage, unconfigured skip, and end to end against a local fake of Roblox" lune run tests/run -- "$A/runner.spec.luau" "$A/runner-e2e.spec.luau"
check "AC4: tests/runtime scripts are strict, require nothing and end by returning PASS; the structure check asserts the place" lune run tests/run -- "$A/scripts.spec.luau"
check "AC5: the beta job runs the runtime tests on the published version; the docs and the testing skill describe them" lune run tests/run -- "$A/pipeline.spec.luau"

finish
