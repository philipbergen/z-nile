#!/usr/bin/env bash
# Acceptance checks for c0490. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0490 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0490"
SPEC="$A/transient.spec.luau"
CASES="$PWD/tests/acceptance"

# the transient spec has one case per rule; each check names the cases it stands for in the issue's Test plan
check "AC1: isTransient is true for 429 and 5xx only" lune run tests/run -- "$SPEC"
check "AC2: a transient failure creating or polling is retried (also through runSuite)" lune run tests/run -- "$SPEC"
check "AC3: retrying is bounded by MAX_ATTEMPTS per request, with the same final error" lune run tests/run -- "$SPEC"
check "AC4: non-transient failures are raised at once" lune run tests/run -- "$SPEC"
check "AC5: the pause is transientSeconds (default 5), not retrySeconds" lune run tests/run -- "$SPEC"
check "AC6: retry pauses do not shorten the task timeout" lune run tests/run -- "$SPEC"
check "AC7: the API key never appears in an error after retries" lune run tests/run -- "$SPEC"
check "AC8: publish and the earlier Open Cloud specs still pass" lune run tests/run -- "$SPEC" "$CASES/c0030/execute.spec.luau" "$CASES/c0030/suite.spec.luau" "$CASES/c0140/publish.spec.luau" "$CASES/c0140/config.spec.luau"
check "AC9: the tracker skill documents rerunning a transient-red beta" bash -c 'f=.claude/skills/tracker/SKILL.md; grep -q "HTTP 429" "$f" && grep -q "opencloud:" "$f" && grep -n "transient" "$f" | grep -q . && grep -q "gh run rerun" "$f"'

finish
