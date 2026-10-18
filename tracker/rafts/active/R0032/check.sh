#!/usr/bin/env bash
# Exit criteria for R0032. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0032); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0032

# the c0064 specs, wherever they are: here before `tracker.sh done`, promoted after it
C="$(scripts/tracker.sh find c0064)/acceptance"
[[ -d $C ]] || C="$PWD/tests/acceptance/c0064"
check "RC1: end to end, deploy and the runtime tests per place pass three times in a row" bash -c 'for i in 1 2 3; do lune run tests/run -- "$1/deploy.spec.luau" "$1/runtime.spec.luau" || exit 1; done' _ "$C"
check "RC2: the game and lobby projects and src are untouched" bash -c 'git diff --quiet origin/main...HEAD -- default.project.json lobby.project.json src'

finish
