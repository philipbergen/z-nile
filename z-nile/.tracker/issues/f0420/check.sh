#!/usr/bin/env bash
# Acceptance checks for f0420. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0420 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0420"

# The spec's cases share one setup, so it runs once (here, outside `check`: list mode refuses it); a check then
# requires its named cases to exist in the spec and not fail, and the spec to have loaded.
report_out=$(lune run tests/run -- "$A/workers-live.spec.luau" 2>&1)
# every case some criterion names: the indented case lines of the check calls below (design review 003 F1)
named=$(grep -E '^  "' "$HERE/check.sh" | sed -E 's/^  "//; s/" ?\\?$//')
is_named() { # $1: a case name; true if a criterion names it (a named prefix)
  local k
  while IFS= read -r k; do [[ -n $k && $1 == "$k"* ]] && return 0; done <<<"$named"
  return 1
}
whole_run() { # the spec's whole run: every case is named by a criterion (but set-up and clean-up), and any failing
  # case that no criterion names (set-up and clean-up included) fails every criterion
  local spec="$A/workers-live.spec.luau" line c failed lines
  # every failure is one `FAIL <file> :: <case>` line: the summary's count must match them (design review 004 F3)
  failed=$(sed -nE 's/^[0-9]+ passed, ([0-9]+) failed, 1 spec files$/\1/p' <<<"$report_out")
  lines=$(grep -cE "^FAIL .* :: " <<<"$report_out")
  [[ $failed == "$lines" ]] || { echo "the run counts ${failed:-no} failure(s) but names $lines:"; tail -20 <<<"$report_out"; return 1; }
  while IFS= read -r line; do
    c=${line#*:: }
    is_named "$c" || { echo "a case no criterion names failed:"; grep -F -A1 -- "$line" <<<"$report_out"; return 1; }
  done < <(grep -E "^FAIL .* :: " <<<"$report_out")
  while IFS= read -r c; do
    [[ $c == "sets up" || $c == "cleans up" ]] && continue
    is_named "$c" || { echo "the spec's case \"$c\" is named by no criterion"; return 1; }
  done < <(tr -d "\n\t" < "$spec" | grep -oE 'it\("[^"]+"' | sed -E 's/^it\("//; s/"$//')
}
report() { # $1...: case-name prefixes that must exist in the spec and not fail; and the spec's whole run (whole_run)
  local spec="$A/workers-live.spec.luau" c
  [[ -f $spec ]] || { echo "missing $spec"; return 1; }
  if grep -q "could not load spec" <<<"$report_out"; then echo "$report_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$report_out" || { echo "$report_out" | tail -20; return 1; }
  whole_run || return 1
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "$spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$report_out" | grep -qF ":: $c"; then grep -F -A1 ":: $c" <<<"$report_out"; return 1; fi
  done
}

check "AC40: a session that runs work next is registered in the live layer with its CLI, its pid, its account label and what it can deliver, once however often it runs" report \
  "AC40 a session that runs work next is registered" \
  "AC40 registering twice is one worker and one registered event"
check "AC41: every work next beats the heartbeat and the unit and activity it was given are the worker's claim" report \
  "AC41 every work next beats the heartbeat" \
  "AC41 every work next sends the daemon a beat" \
  "AC41 the worker's other zn commands beat too" \
  "AC41 the unit and the activity the worker was given are its claim"
check "AC42: two workers at once are both registered, the second is not given the unit the first holds and is told who holds it, and can take it after the first releases" report \
  "AC42 two workers at once" \
  "AC42 a unit another worker holds is refused when named" \
  "AC42 a unit another worker wins first" \
  "AC42 when the first worker releases" \
  "AC42 a named raft another worker holds" \
  "AC42 a named raft whose dependency raft" \
  "AC42 a named issue another worker holds" \
  "AC42 two workers started at the same instant"
check "AC43: the claim ends with the next action, and a worker whose process is gone is lost and its unit freed" report \
  "AC43 the claim ends with the next action" \
  "AC43 a worker whose process is gone" \
  "AC43 ./zn stop gives back the live claim"
check "AC44: with the layer off, absent or refusing the output and exit code are the same and nothing is registered" report \
  "AC44 with the layer off" \
  "AC44 with no daemon binary" \
  "AC44 a daemon that is stopped" \
  "AC44 a nested CLI under ./zn dispatch"
check "AC45: an account label that is not a short safe word is not sent, and no worker registers in a default state folder from a spec" report \
  "AC45 an account label" \
  "AC45 an older daemon that refuses --account" \
  "AC45 no worker is registered in a default state folder"
check "AC40: the worker is the CLI's own process even with no ZN_WORKER_PID" report \
  "AC40 a session with no ZN_WORKER_PID"
check "AC46: the worker module reads no credential, token, email or CLI config, no dynamic variable and only named modules" report \
  "AC46 the worker module reads no credential"

finish
