#!/usr/bin/env bash
# Acceptance checks for c0059. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0059 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0059"

spec="$A/adapt.spec.luau"
# The spec's cases share one fixture, so it runs once (here, outside `check`: list mode refuses it); each
# check then requires its named cases to exist in the spec and not fail, and the spec to have loaded.
spec_out=$(lune run tests/run -- "$spec" 2>&1)
cases_pass() { # $@: case-name prefixes that must exist in the spec and not appear in a FAIL line
  if grep -q "could not load spec" <<<"$spec_out"; then echo "$spec_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out"; return 1; }
  local c
  for c in "$@"; do
    grep -qF "it(\"$c" "$spec" || { echo "the spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$spec_out" | grep -qF ":: $c"; then grep -F -A3 ":: $c" <<<"$spec_out"; return 1; fi
  done
}

check "AC1: c0053's promoted specs set no fence of their own and pass the gate's scan, which lets them name only what their fixture hooks unset" cases_pass \
  "c0053's specs set no fence of their own, and pass the gate's scan" \
  "c0053's specs may name only what their fixture hooks unset"
check "AC2: a check run publishes nothing, says so and still works locally; outside it publishes" cases_pass \
  "a check run publishes nothing, says so, and still works" \
  "outside the guards' protection the same command publishes" \
  "a check run's status move publishes nothing either, and says so"
check "AC3: the full gate passes" ./check.sh --full
check "AC4: the testing skill says a check never publishes tracker state" bash -c '
  s=skills/zz-test/SKILL.md
  grep -qiE "never publish|not publishing|publishes nothing" "$s" || { echo "the testing skill does not say checks never publish"; exit 1; }'

finish
