#!/usr/bin/env bash
# Exit criteria for R0034. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(./zn members R0034); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ./zn promote-check R0034

# a sequestered issue spec before `./zn done`, its promoted copy after it
spec() { # $1 issue id, $2 spec name
  local f
  f="$(./zn find "$1")/acceptance/$2.spec.luau"
  [[ -f $f ]] || f="tests/acceptance/$1/$2.spec.luau"
  echo "$f"
}

way_back_end_to_end() {
  local i
  for i in 1 2 3; do
    lune run tests/run -- "$(spec f0065 run)" "$(spec f0065 returns)" "$(spec f0065 sessions)" "$(spec f0065 place)" "$(spec f0065 client)" \
      tests/acceptance/f0031/*.spec.luau tests/acceptance/f0061/*.spec.luau >/dev/null 2>&1 \
      || { echo "the way-back specs fail on repeat $i"; return 1; }
  done
}
check "RC1: from game over back to the lobby, end to end, three times in a row, beside f0031's narrowed and f0061's lobby specs" way_back_end_to_end

lobby_untouched() {
  git diff --quiet "$(git merge-base origin/main HEAD)" -- lobby.project.json src/lobby src/shared/Logic/Travel \
    || { echo "the lobby or Travel changed"; return 1; }
}
check "RC2: the lobby and Travel are untouched" lobby_untouched

finish
