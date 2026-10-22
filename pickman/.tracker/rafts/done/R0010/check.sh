#!/usr/bin/env bash
# Exit criteria for R0010. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" z-nile/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(./zn members R0010); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ./zn promote-check R0010

# a sequestered issue spec before `./zn done`, its promoted copy after it
spec() { # $1 issue id, $2 spec name
  local f="tracker/issues/active/$1/acceptance/$2.spec.luau"
  [[ -f $f ]] || f="tracker/issues/$1/acceptance/$2.spec.luau"
  [[ -f $f ]] || f="tests/acceptance/$1/$2.spec.luau"
  echo "$f"
}

end_to_end() {
  lune run tests/run -- "$(spec f0023 idle-player)" "$(spec f0023 session-ghosts)" "$(spec f0032 frame)"
}
check "RC1: end to end through Session with GAME_CONFIG the ghosts hunt (an idle player is caught within 8 to 20 s on 20 seeds), the blue time ends with the run's power, and the frame carries the ghosts" end_to_end

stable_and_compatible() {
  local i files
  files="$(spec f0020 targets) $(spec f0020 exits) $(spec f0020 walking) $(spec f0021 schedule) $(spec f0021 frightened) $(spec f0022 release) $(spec f0022 eyes) $(spec f0023 contacts) $(spec f0023 session-ghosts) $(spec f0023 idle-player) $(spec f0032 frame) $(spec f0033 awareness)"
  for i in 1 2 3; do
    # shellcheck disable=SC2086
    lune run tests/run -- $files >/dev/null 2>&1 || { echo "the ghost specs fail on repeat $i"; return 1; }
  done
  # the existing session and client specs run with ghosts on in GAME_CONFIG
  files=$(find tests/acceptance/f0013 tests/acceptance/f0016 tests/acceptance/f0017 tests/acceptance/f0018 tests/acceptance/f0054 tests/acceptance/f0014 -name '*.spec.luau' | sort)
  # shellcheck disable=SC2086
  lune run tests/run -- $files >/dev/null 2>&1 || { echo "an existing session or client spec fails"; return 1; }
}
check "RC2: the ghost specs pass three times in a row (no shared fixture state), and the existing session and client specs still pass" stable_and_compatible

finish
