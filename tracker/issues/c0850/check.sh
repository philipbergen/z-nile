#!/usr/bin/env bash
# Acceptance checks for c0850. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0850 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0850"

# The spec's cases share one setup, so it runs once (here, outside `check`: list mode refuses it); a check then
# requires its named cases to exist in the spec and not fail, and the spec to have loaded.
watchdog_out=$(lune run tests/run -- "$A/watchdog.spec.luau" 2>&1)
cases_in() { # $1: spec file, $2: its output, $3...: case-name prefixes that must exist and not fail
  local spec=$1 out=$2 c; shift 2
  [[ -f $spec ]] || { echo "missing $spec"; return 1; }
  if grep -q "could not load spec" <<<"$out"; then echo "$out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$out" || { echo "$out" | tail -20; return 1; }
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "$spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$out" | grep -qF ":: $c"; then grep -F -A3 ":: $c" <<<"$out"; return 1; fi
  done
}
watchdog() { cases_in "$A/watchdog.spec.luau" "$watchdog_out" "$@"; }

check "AC1: when the launcher is killed, the command it ran is gone within 3 seconds" watchdog \
  "when the launcher is killed, the command it ran is stopped within 3 seconds"
check "AC2: the watchdog outlives INT, TERM and HUP the launcher forwards" watchdog \
  "the watchdog outlives INT, TERM and HUP forwarded to the group"
check "AC3: a normal end passes the status through and leaves nothing of the group" watchdog \
  "a normal end passes the command's status through and leaves nothing of its group behind"
check "AC4: every fork in the launcher is checked; the watchdog waits on a pipe; the end runs wait, kill, unlink, exit" watchdog \
  "every fork in the launcher is checked, the watchdog waits on a pipe, and the end runs in order"

finish
