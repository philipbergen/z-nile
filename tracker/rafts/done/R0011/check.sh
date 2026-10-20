#!/usr/bin/env bash
# Exit criteria for R0011. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0011); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0011

# a sequestered issue spec before `tracker.sh done`, its promoted copy after it
spec() { # $1 issue id, $2 spec name
  local f
  f="$(scripts/tracker.sh find "$1")/acceptance/$2.spec.luau"
  [[ -f $f ]] || f="tests/acceptance/$1/$2.spec.luau"
  echo "$f"
}

check "RC1: a submitted score shows on the all-time panel and the day board, and ranks once" lune run tests/run -- "$(spec f0026 endtoend)"

hiscores_feature_has_no_edge() {
  local block
  block="$(sed -n '/^```deps$/,/^```$/p' tracker/architecture.md)"
  if grep -q 'Hiscores' <<<"$block"; then
    echo "the deps block names Hiscores"
    return 1
  fi
  grep -q '^| Hiscores |' tracker/architecture.md || {
    echo "the features table has no Hiscores row"
    return 1
  }
}
check "RC2: Hiscores is a feature and the deps block does not name it" hiscores_feature_has_no_edge

finish
