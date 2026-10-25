#!/usr/bin/env bash
# Exit criteria for R0024. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" ../z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(../zn members R0024); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ../zn promote-check R0024

# a sequestered issue spec before `./zn done`, its promoted copy after it
spec() { # $1 issue id, $2 spec name
  local f
  f="$(../zn find "$1")/acceptance/$2.spec.luau"
  [[ -f $f ]] || f="tests/acceptance/$1/$2.spec.luau"
  echo "$f"
}

lobby_end_to_end() {
  local i
  for i in 1 2 3; do
    lune run tests/run -- "$(spec f0061 lobby-run)" "$(spec f0061 lobby-place)" "$(spec f0061 lobby-adapters)" >/dev/null 2>&1 \
      || { echo "the lobby specs fail on repeat $i"; return 1; }
  done
}
check "RC1: the lobby, built from its own project, runs as a player lives it (press, failure, wait, retry, teleport) and the specs pass three times in a row with no shared state" lobby_end_to_end

game_place_untouched() {
  local files
  files=$(find tests/acceptance/f0013 tests/acceptance/f0014 tests/acceptance/f0018 tests/acceptance/f0019 tests/acceptance/f0030 tests/acceptance/f0031 tests/acceptance/f0054 tests/acceptance/c0002 tests/place -name '*.spec.luau' | sort)
  # shellcheck disable=SC2086
  lune run tests/run -- $files >/dev/null 2>&1 || { echo "a game place spec fails"; return 1; }
  git diff --quiet "$(git merge-base origin/main HEAD)" -- default.project.json src/server src/client || { echo "the game place changed"; return 1; }
}
check "RC2: the game place is untouched: default.project.json, src/server and src/client are as they were when the branch left main, and its place and adapter specs pass" game_place_untouched

finish
