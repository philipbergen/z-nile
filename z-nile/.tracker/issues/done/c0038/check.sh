#!/usr/bin/env bash
# Acceptance checks for c0038. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0038 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0038"

spec="$A/deferred.spec.luau"
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

check "AC1: a deferred answer is refused when the finding is high or unrated, the target is missing or not in the backlog, or id/reason is missing" cases_pass \
  "refuses to defer a high finding" "refuses to defer to an issue that does not exist" \
  "refuses to defer to an issue that is not in the backlog" "refuses a deferral that names no issue" \
  "refuses to defer a finding whose severity is not stated"
check "AC2: fixed and refuted still work, other words stay unanswered, and a valid deferral finishes done" cases_pass \
  "still accepts fixed and refuted" "finishes when medium and low findings are deferred"
check "AC3: the skills document deferred and drop the interim form" bash -c '
  x=.claude/skills/execute-raft/SKILL.md; t=.claude/skills/tracker/SKILL.md
  grep -qF -- "- F<n>: deferred <id>: <why>" "$x" || { echo "execute-raft lacks the deferred form"; exit 1; }
  grep -qF -- "deferred <id>" "$t" || { echo "tracker skill lacks deferred"; exit 1; }
  for s in "interim form" "refuted: below the merge threshold"; do
    if grep -qF -- "$s" "$x"; then echo "execute-raft still has: $s"; exit 1; fi
  done'

finish
