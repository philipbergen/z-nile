#!/usr/bin/env bash
# Acceptance checks for f0024. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/f0024 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0024"

check "AC1: UTC day and Monday-start week keys, including the epoch, a Sunday, and a date that is not the local day" lune run tests/run -- "$A/period.spec.luau"
check "AC2: a row is replaced only by a strictly higher score, or an equal score with a strictly higher level" lune run tests/run -- "$A/replace.spec.luau"
check "AC3: the top N is the sorted real rows, with a short page left short and no hard-coded list" lune run tests/run -- "$A/rows.spec.luau"
check "AC4: the fake keeps one row per user per board, and N stays 10" lune run tests/run -- "$A/store.spec.luau"
check "AC5: retry, backoff and budget are pure, and a zero list budget still reads the top" lune run tests/run -- "$A/drive.spec.luau"
check "AC6: the feature stays free of the engine and the adapter calls that policy" lune run tests/run -- "$A/adapter.spec.luau"

finish
