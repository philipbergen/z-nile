#!/usr/bin/env bash
# Acceptance checks for c0066. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0066 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0066"

check "AC1-AC2: cleanup.removeTree removes, retries a racing writer, gives up with a diagnosis, raises other errors at once" \
  lune run tests/run -- "$A/cleanup.spec.luau"
check "AC3: c0038's cleans up case uses cleanup.removeTree, and the spec passes" bash -c '
  s=tests/acceptance/c0038/deferred.spec.luau
  tr -d "\n\t" < "$s" | grep -qF "it(\"cleans up\", function()cleanup.removeTree(work)" || { echo "cleans up does not use cleanup.removeTree(work)"; exit 1; }
  lune run tests/run -- "$s"'

finish
