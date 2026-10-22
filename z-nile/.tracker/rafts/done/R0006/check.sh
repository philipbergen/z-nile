#!/usr/bin/env bash
# Exit criteria for R0006. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(./zn members R0006); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ./zn promote-check R0006

# RC1: on the real tracker, regenerating gives the same bytes and leaves the working tree untouched
# (the page goes to the gitignored .cache/).
board_is_stable() {
  local before after
  before=$(git status --porcelain)
  ./zn board --out .cache/r0060-a.html >/dev/null || return 1
  ./zn board --out .cache/r0060-b.html >/dev/null || return 1
  cmp -s .cache/r0060-a.html .cache/r0060-b.html || { echo "regeneration differs"; return 1; }
  after=$(git status --porcelain)
  rm -f .cache/r0060-a.html .cache/r0060-b.html
  [ "$before" = "$after" ] || { echo "tree changed:"; diff <(echo "$before") <(echo "$after"); return 1; }
}
check "RC1: ./zn board is byte-stable on the real tracker and leaves git status unchanged" board_is_stable

finish
