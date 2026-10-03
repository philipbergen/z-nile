#!/usr/bin/env bash
# Exit criteria for R0100. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0100); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0100

# a sequestered issue spec before `tracker.sh done`, its promoted copy after it
spec() { # $1 issue id, $2 spec name
  local f="tracker/issues/$1/acceptance/$2.spec.luau"
  [[ -f $f ]] || f="tests/acceptance/$1/$2.spec.luau"
  echo "$f"
}

end_to_end() {
  lune run tests/run -- "$(spec f0220 idle-player)" "$(spec f0220 session-ghosts)" "$(spec f0310 frame)"
}
check "RC1: end to end through Session with GAME_CONFIG the ghosts hunt (an idle player is caught within 8 to 20 s on 20 seeds), the blue time ends with the run's power, and the frame carries the ghosts" end_to_end

stable_and_compatible() {
  local i files
  files="$(spec f0190 targets) $(spec f0190 exits) $(spec f0190 walking) $(spec f0200 schedule) $(spec f0200 frightened) $(spec f0210 release) $(spec f0210 eyes) $(spec f0220 contacts) $(spec f0220 session-ghosts) $(spec f0220 idle-player) $(spec f0310 frame) $(spec f0320 awareness)"
  for i in 1 2 3; do
    # shellcheck disable=SC2086
    lune run tests/run -- $files >/dev/null 2>&1 || { echo "the ghost specs fail on repeat $i"; return 1; }
  done
  # the existing session and client specs run with ghosts on in GAME_CONFIG
  files=$(find tests/acceptance/f0120 tests/acceptance/f0150 tests/acceptance/f0160 tests/acceptance/f0170 tests/acceptance/f0520 tests/acceptance/f0130 -name '*.spec.luau' | sort)
  # shellcheck disable=SC2086
  lune run tests/run -- $files >/dev/null 2>&1 || { echo "an existing session or client spec fails"; return 1; }
}
check "RC2: the ghost specs pass three times in a row (no shared fixture state), and the existing session and client specs still pass" stable_and_compatible

finish
