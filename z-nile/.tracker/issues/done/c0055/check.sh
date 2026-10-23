#!/usr/bin/env bash
# Acceptance checks for c0055. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0055 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0055"

check "AC1: with no argument, setup.sh installs the tools, then runs the gate once with --full, last" lune run tests/run -- "$A/setup-run.spec.luau"
check "AC2: --tools installs the tools and runs no gate" lune run tests/run -- "$A/setup-run.spec.luau"
check "AC3: neither CI nor any variable skips the gate; the CI branches run on CI" lune run tests/run -- "$A/setup-run.spec.luau"
check "AC4: a red gate fails setup with its exit code and no SETUP OK" lune run tests/run -- "$A/setup-run.spec.luau"
check "AC5: an unknown argument exits 2 and runs nothing" lune run tests/run -- "$A/setup-run.spec.luau"
check "AC6: a host without rokit installs the pinned release, then runs the gate" lune run tests/run -- "$A/setup-run.spec.luau"
check "AC7: the spec leaves no fixture behind" bash -c 'lune run tests/run -- "$0" >/dev/null && [[ ! -e .cache/c0055-setup ]]' "$A/setup-run.spec.luau"
check "AC8: the slice-based setup-tools spec is gone and no other check.sh names it" bash -c '[[ ! -e tests/acceptance/c0048/setup-tools.spec.luau ]] && ! grep -rl --include=check.sh "setup-tools.spec" tracker | grep -v "/c0055/check.sh$"'
check "AC9: c0015's text spec still passes" lune run tests/run -- tests/acceptance/c0015/tools.spec.luau

finish
