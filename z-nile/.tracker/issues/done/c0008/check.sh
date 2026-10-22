#!/usr/bin/env bash
# Acceptance checks for c0008. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0008 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0008"

spec="$A/done-order.spec.luau"
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

check "AC1: done marks the PR ready while origin has the previous head, then pushes; a refused done never marks it" cases_pass \
  "marks the PR ready while origin still has the previous head" "does not mark the PR ready when done refuses"
check "AC2: a gh failure rolls done back (HEAD, tree, raft state, nothing pushed)" cases_pass \
  "rolls back and stays active when gh cannot mark the PR ready"
check "AC3: the skills document the new order and drop the old one" bash -c '
  t=../.claude/skills/tracker/SKILL.md; x=../.claude/skills/execute-raft/SKILL.md
  for s in "marks the PR **ready** before its final push" "the push starts the \`pull_request\` run"; do
    grep -qF -- "$s" "$t" || { echo "tracker skill is missing: $s"; exit 1; }
  done
  grep -qF -- "marks the PR ready, then moves the items" "$x" || { echo "execute-raft Phase 5 is missing the new order"; exit 1; }
  for s in "\`done\` pushes and then marks the PR ready" "of the ready event"; do
    if grep -qF -- "$s" "$t"; then echo "tracker skill still says: $s"; exit 1; fi
  done
  if grep -qF -- "pushes, and marks the PR ready" "$x"; then echo "execute-raft still says the old order"; exit 1; fi'

finish
