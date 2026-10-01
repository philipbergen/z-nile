#!/usr/bin/env bash
# Acceptance checks for c0460. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance" # sequestered specs; see the testing skill
source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "AC1: board.yml triggers only on push to main and dispatch, read-only, per-ref concurrency, main-only job, no hidden conditions" lune run tests/run -- "$A/board-workflow.spec.luau"
check "AC2: board.yml sets up, builds dist/board.html, and uploads that file as tracker-board, in that order" lune run tests/run -- "$A/board-workflow.spec.luau"
check "AC3: setup.sh stage run against a stub gate: runs when unset or empty, skips when set; no other call or setter; SETUP.md documents it" lune run tests/run -- "$A/setup-skip-gate.spec.luau"
check "AC4: the tracker skill's board row says how to fetch the artifact" lune run tests/run -- "$A/board-docs.spec.luau"
check "AC5: the board builds with the workflow's own command" bash -c 'out=$(mktemp -d)/dist/board.html && scripts/tracker.sh board --out "$out" >/dev/null && grep -q "board-data" "$out"'
check "AC6: the acceptance specs are formatted and linted" bash -c 'stylua --check "$0" && selene --quiet "$0"' "$A"
check "AC7: the full gate passes" scripts/check.sh --full

finish
