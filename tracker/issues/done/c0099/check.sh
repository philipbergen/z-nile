#!/usr/bin/env bash
# Acceptance checks for c0099. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0099 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0099"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
spec() { local d; d=$(scripts/tracker.sh find c0077) || return 1
  if [[ -f $d/acceptance/replace-file.spec.luau ]]; then echo "$d/acceptance/replace-file.spec.luau"; else echo tests/acceptance/c0077/replace-file.spec.luau; fi; }
check "AC1: the stub rojo links .cache/check.rbxl only for the game place's build" bash -c '
  grep -qF "if [ \"\$1\" = build ] && [ \"\$2\" = default.project.json ]; then rm -f .cache/check.rbxl" "$1" || { echo "the stub links on every build"; exit 1; }' _ "$(spec)"
five_runs() { local i; for i in 1 2 3 4 5; do lune run tests/run -- "$(spec)" || return 1; done; }
check "AC2: c0077's replace-file spec passes five runs in a row" five_runs

finish
