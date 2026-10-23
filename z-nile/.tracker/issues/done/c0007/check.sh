#!/usr/bin/env bash
# Acceptance checks for c0007. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0007 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0007"

spec="$A/changed.spec.luau"
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

check "AC1: changed.files lists every kind of change, both paths of a move, nothing from the base after the fork" cases_pass \
  "lists committed, staged, unstaged and untracked changes" "lists a moved file at both" \
  "does not list what changed on the base after" "with no usable base"
check "AC2: the default base is origin/main when it exists, else main" cases_pass \
  "defaults to main when there is no origin" "defaults to origin/main when it exists"
check "AC3: z-nile/affected uses the module, and the affected specs still pass" bash -c '
  lune run tests/run -- tests/tooling/affected.spec.luau &&
  grep -qF "scripts/affected takes its changed files from the module" "'"$spec"'" &&
  lune run tests/run -- "'"$spec"'" 2>&1 | grep -E "^[0-9]+ passed, 0 failed" >/dev/null'

finish
