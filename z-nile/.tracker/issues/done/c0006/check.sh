#!/usr/bin/env bash
# Acceptance checks for c0006. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0006 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0006"

spec="$A/clone.spec.luau"
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

check "AC1: clone.isolated shares no object file with the repository, and a failed clone names its source" cases_pass \
  "an isolated clone shares no object file with the repo" "a failed clone is an error that names the source"
check "AC2: no spec clones the repository with a plain git clone" cases_pass \
  "no spec clones the repository with a plain git clone"
check "AC3: SETUP.md warns against a cloud-synced checkout" cases_pass \
  "SETUP.md warns against a checkout in a cloud-synced folder"

finish
