#!/usr/bin/env bash
# Acceptance checks for c0074. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0074 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0074"

# The spec's cases share one fixture, so it runs once (here, outside `check`: list mode refuses it); a check then
# requires its named cases to exist in the spec and not fail, and the spec to have loaded.
gate_out=$(lune run tests/run -- "$A/done-gate.spec.luau" 2>&1)
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
gate() { cases_in "$A/done-gate.spec.luau" "$gate_out" "$@"; }

check "AC1: with the gate in force, done runs the full gate once on the promoted, moved tree, then commits" gate \
  "done runs the full gate on the promoted, moved tree, then commits"
check "AC2: a failing gate rolls everything back and leaves the raft active" gate \
  "a failing gate rolls everything back and leaves the raft active"
check "AC3: inside a spec run, without the switch, done skips the gate (saying so) and checks the promoted specs" gate \
  "inside a spec run, without the switch, done checks the promoted specs and does not run the gate"
check "AC4: done's promoted fixture specs pass" lune run tests/run -- \
  tests/acceptance/c0001/tracker-lifecycle.spec.luau tests/acceptance/c0008/done-order.spec.luau \
  tests/acceptance/c0034/locator.spec.luau tests/acceptance/c0038/deferred.spec.luau \
  tests/acceptance/c0045/workstreams.spec.luau tests/acceptance/c0050/start-depends.spec.luau

check "AC5: the tracker skill's done row states the full gate and how to recover from an interrupted gate" bash -c '
  row=$(grep -E "^\| done \|" ../.claude/skills/tracker/SKILL.md)
  [[ -n $row ]] || { echo "the tracker skill has no done row"; exit 1; }
  grep -qi "full gate" <<<"$row" || { echo "the done row does not say done runs the full gate"; exit 1; }
  grep -qi "interrupt" <<<"$row" || { echo "the done row does not say how to recover from an interrupted gate"; exit 1; }
  grep -qF "git reset --hard HEAD" <<<"$row" || { echo "the done row does not give the recovery command"; exit 1; }'

check "AC6: the gate decision is full unless inside a spec run without the switch, and done decides through it" gate \
  "the gate decision: full, unless inside a spec run without the switch"

finish
