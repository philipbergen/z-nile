#!/usr/bin/env bash
# Acceptance checks for c0140. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0140 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0140"

check "AC1: OpenCloud.publish: the proven request, busy retries only, the key never in a message" lune run tests/run -- "$A/publish.spec.luau"
check "AC2: configFromEnv: not configured is a skip, ids are digits, the base override is loopback only" lune run tests/run -- "$A/config.spec.luau"
check "AC3: scripts/deploy-beta end to end against a local fake of Roblox, and its unconfigured and failing paths" lune run tests/run -- "$A/deploy-cli.spec.luau" "$A/deploy-e2e.spec.luau"
check "AC4: the beta job in check.yml: after the gate, ready PRs of this repo only, one at a time, secrets in one place" lune run tests/run -- "$A/workflow.spec.luau"
check "AC5: scripts/setup.sh --tools installs the toolchain and skips the gate" lune run tests/run -- "$A/tools.spec.luau"
check "AC6: SETUP.md documents Beta publishing" lune run tests/run -- "$A/docs.spec.luau"

finish
