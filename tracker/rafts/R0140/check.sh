#!/usr/bin/env bash
# Exit criteria for R0140. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0140); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0140

gate_run() { # full gate, output kept for RC1
  GATE_OUT=$(scripts/check.sh --full 2>&1) && GATE_RC=0 || GATE_RC=$?
}
gate_run
gate_reports_speed() {
  [[ $GATE_RC -eq 0 ]] || { echo "$GATE_OUT" | tail -20; return 1; }
  grep -Eq "^slowest: .*\.spec\.luau [0-9]+\.[0-9]s" <<<"$GATE_OUT" || { echo "no slowest: line"; return 1; }
  grep -Eq "^gate wall time: [0-9]+\.[0-9]s$" <<<"$GATE_OUT" || { echo "no wall time line"; return 1; }
  [[ $(tail -n 1 <<<"$GATE_OUT") == "GATE PASSED (full)" ]] || { echo "GATE PASSED (full) is not the last line"; return 1; }
}
check "RC1: a full gate run prints stage times, slowest specs and the wall time, and ends with GATE PASSED (full)" gate_reports_speed

stable_and_serial_fallback() {
  local i
  for i in 1 2 3; do scripts/check.sh --full >/dev/null 2>&1 || { echo "full gate failed on repeat $i"; return 1; }; done
  PICKMAN_JOBS=1 lune run tests/run >/dev/null 2>&1 || { echo "the suite fails with PICKMAN_JOBS=1"; return 1; }
}
check "RC2: the full gate passes three runs in a row, and PICKMAN_JOBS=1 runs the suite green" stable_and_serial_fallback

finish
