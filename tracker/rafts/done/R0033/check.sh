#!/usr/bin/env bash
# Exit criteria for R0033. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(./zn members R0033); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ./zn promote-check R0033

only_specs_changed() {
  local base changed
  base="$(git merge-base origin/main HEAD)"
  changed="$(git diff --name-only "$base" -- . ':!tracker' ':!tests/acceptance/f0031' ':!tests/acceptance/c0063')"
  [[ -z $changed ]] || { echo "changed outside the f0031 specs: $changed"; return 1; }
  [[ -z "$(git diff --name-only --diff-filter=D "$base" -- tests/acceptance/f0031)" ]] || { echo "an f0031 spec was deleted"; return 1; }
}
check "RC1: only f0031's promoted specs (plus tracker files and c0063's own promoted spec) changed, and none was deleted" only_specs_changed

finish
