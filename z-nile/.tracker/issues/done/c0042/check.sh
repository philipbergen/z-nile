#!/usr/bin/env bash
# Acceptance checks for c0042. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0042 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0042"

check "AC1: board.collect builds the designed model (status, raft deps, tabs, No raft, home)" lune run tests/run -- "$A/model.spec.luau"
check "AC2: the page is one byte-stable, self-contained HTML file with escaped JSON data" lune run tests/run -- "$A/page.spec.luau"
check "AC3: tracker.sh board writes the page (--out, default .cache/board.html)" lune run tests/run -- "$A/cli.spec.luau"
check "AC4: marked 18.0.14 is vendored, pinned by sha256, with its licence" lune run tests/run -- "$A/vendor.spec.luau"
check "AC5: the tracker skill documents tracker.sh board" \
  bash -c 'f=.claude/skills/tracker/SKILL.md; for s in "tracker.sh board" ".cache/board.html" "--open"; do grep -qF -- "$s" "$f" || { echo "missing: $s"; exit 1; }; done'
check "AC6: the page's scripts run: node drives tabs, keys, search, highlight and #id links" lune run tests/run -- "$A/smoke.spec.luau"

finish
