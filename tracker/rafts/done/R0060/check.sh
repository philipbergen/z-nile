#!/usr/bin/env bash
# Exit criteria for R0060. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0060); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0060

# RC1: on the real tracker, regenerating gives the same bytes and leaves the working tree untouched
# (the page goes to the gitignored .cache/).
board_is_stable() {
  local before after
  before=$(git status --porcelain)
  scripts/tracker.sh board --out .cache/r0060-a.html >/dev/null || return 1
  scripts/tracker.sh board --out .cache/r0060-b.html >/dev/null || return 1
  cmp -s .cache/r0060-a.html .cache/r0060-b.html || { echo "regeneration differs"; return 1; }
  after=$(git status --porcelain)
  rm -f .cache/r0060-a.html .cache/r0060-b.html
  [ "$before" = "$after" ] || { echo "tree changed:"; diff <(echo "$before") <(echo "$after"); return 1; }
}
check "RC1: tracker.sh board is byte-stable on the real tracker and leaves git status unchanged" board_is_stable

finish
