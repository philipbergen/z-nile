#!/usr/bin/env bash
# Acceptance checks for c0460. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0460 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0460"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: board.yml triggers only on push to main and dispatch, read-only, per-ref concurrency, main-only job, no hidden conditions" lune run tests/run -- "$A/board-workflow.spec.luau"
check "AC2: board.yml sets up, builds dist/board.html, and uploads that file as tracker-board, in that order" lune run tests/run -- "$A/board-workflow.spec.luau"
check "AC3: setup.sh's tools-only mode skips the gate only for --tools (c0140's text spec; the behavioural run of the whole script is c0530's)" lune run tests/run -- tests/acceptance/c0140/tools.spec.luau
check "AC4: the tracker skill's board row says how to fetch the artifact" lune run tests/run -- "$A/board-docs.spec.luau"
check "AC5: the board builds with the workflow's own command" bash -c 'out=$(mktemp -d)/dist/board.html && scripts/tracker.sh board --out "$out" >/dev/null && grep -q "board-data" "$out"'
check "AC6: the acceptance specs are formatted and linted" bash -c 'stylua --check "$0" && selene --quiet "$0"' "$A"
check "AC7: the full gate passes" scripts/check.sh --full

finish
