#!/usr/bin/env bash
# Acceptance checks for c0132. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0132 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0132"

# The spec's cases share one setup, so it runs once (here, outside `check`: list mode refuses it); a check then
# requires its named cases to exist in the spec and not fail, and the spec to have loaded.
report_out=$(lune run tests/run -- "$A/killed-report.spec.luau" 2>&1)
report() { # $1...: case-name prefixes that must exist in the spec and not fail
  local spec="$A/killed-report.spec.luau" c
  [[ -f $spec ]] || { echo "missing $spec"; return 1; }
  if grep -q "could not load spec" <<<"$report_out"; then echo "$report_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$report_out" || { echo "$report_out" | tail -20; return 1; }
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "$spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$report_out" | grep -qF ":: $c"; then grep -F -A3 ":: $c" <<<"$report_out"; return 1; fi
  done
}

check "AC1: a killed sweeper's report names the launcher, the run's top process and whether it lives, and the specs' group" report \
  "a sweeper killed alone: the report names the launcher, the live top process and the specs' group" \
  "the report says when the run's top process is gone"
check "AC2: the report says whether the watchdog lives and lists every other process still in the group, before the group is stopped" report \
  "a sweeper killed alone: the watchdog is alive and every process still in the group is listed" \
  "a whole group killed: the watchdog is gone and nothing is left in the group" \
  "the group is still stopped after the report"
check "AC3: the report says when, how many seconds after the specs started, and the memory the OS saw when the sweeper died" report \
  "the report says when, and how long after the specs started, the sweeper died" \
  "the report gives the memory the OS saw: percent free and swap used, read on macOS"
check "AC4: no report without a sweeper or without a signal death" report \
  "a launcher not running a sweeper reports nothing, and a signal death stays 128+n" \
  "a sweeper that exits, even with a failing status, gets no report"
check "AC5: the runner gives its launcher its own pid as PICKMAN_REAP_TOP, and no spec inherits it" report \
  "the runner gives its launcher its own pid as PICKMAN_REAP_TOP, and no spec inherits it"
check "AC6: the testing skill says how to read the report" report \
  "the testing skill says how to read a killed sweeper's report"

finish
