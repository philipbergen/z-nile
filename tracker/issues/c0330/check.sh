#!/usr/bin/env bash
# Acceptance checks for c0330. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0330 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0330"

spec="$A/locator.spec.luau"
# The spec's cases share one fixture, so it runs once; each check then requires its own named cases to
# exist in the spec and not fail, and that the spec loaded at all.
spec_out=$(lune run tests/run -- "$spec" 2>&1)
cases_pass() { # $@: case-name prefixes that must exist in the spec and not appear in a FAIL line
  if grep -q "could not load spec" <<<"$spec_out"; then echo "$spec_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out"; return 1; }
  local c
  for c in "$@"; do
    grep -qF "it(\"$c" "$spec" || { echo "the spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$spec_out" | grep -qF ":: $c"; then grep -F ":: $c" <<<"$spec_out"; return 1; fi
  done
}

check "AC1: AC_LIST=1 lists a check without running it; without it checks run" cases_pass \
  "AC_LIST=1 lists a check without running it"
check "AC2: the issue template's check.sh works before and after promotion" cases_pass \
  "the issue template's check.sh works before and after"
check "AC3: every finished item's check.sh finds the repo, and no live one uses the old locator" cases_pass \
  "every finished item's check.sh finds the repo" "no live check.sh or the template uses the locator"
check "AC4: list mode can't be mistaken for a pass or re-run specs (runner, top-level specs, tracker.sh check)" cases_pass \
  "the spec runner refuses to run specs when AC_LIST is set" \
  "a check.sh that runs a spec at top level only lists in list mode" \
  "tracker.sh check refuses to run with AC_LIST set"
check "AC5: the testing skill shows the new locator and AC_LIST" bash -c '
  f=.claude/skills/testing/SKILL.md
  for s in "AC_LIST=1" "[[ -d \$A ]] || A=\"\$PWD/tests/acceptance/"; do
    grep -qF -- "$s" "$f" || { echo "missing: $s"; exit 1; }
  done
  if grep -qF "git -C \"\$A/..\"" "$f"; then echo "the old locator is still in the example"; exit 1; fi'

finish
