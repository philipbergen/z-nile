#!/usr/bin/env bash
# Acceptance checks for c0051. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0051 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0051"
OLD="$PWD/tests/acceptance"

check "AC1: isTransient is true for 429 and 5xx only" lune run tests/run -- "$A/classify.spec.luau"
check "AC2: a transient failure creating or polling is retried (also through runSuite)" lune run tests/run -- "$A/retry.spec.luau"
check "AC3: failures that are not transient are raised at once (publish included)" lune run tests/run -- "$A/final.spec.luau"
check "AC4: retrying is bounded per request and by the per-execute pause cap" lune run tests/run -- "$A/bounds.spec.luau"
check "AC5: the pause is transientSeconds (default 5) on creation and polling" lune run tests/run -- "$A/pauses.spec.luau"
check "AC6: retry pauses do not shorten the task timeout" lune run tests/run -- "$A/pauses.spec.luau"
check "AC7: publish retries 409 and 429/5xx within one MAX_ATTEMPTS budget" lune run tests/run -- "$A/publish.spec.luau" "$OLD/c0015/publish.spec.luau" "$OLD/c0015/config.spec.luau"
check "AC8: the API key never appears in an error after retries" lune run tests/run -- "$A/key.spec.luau" "$OLD/c0003/execute.spec.luau" "$OLD/c0003/suite.spec.luau"
check "AC9: one line of the tracker skill covers a transient-red beta" bash -c 'grep -n "HTTP 429" .claude/skills/tracker/SKILL.md | grep "opencloud:" | grep "gh run rerun" | grep -qi "transient"'

finish
