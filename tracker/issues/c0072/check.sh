#!/usr/bin/env bash
# Acceptance checks for c0072. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0072 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0072"

spec="$A/land.spec.luau"
spec_out=$(lune run tests/run -- "$spec" 2>&1)
cases_pass() { # $@: case-name prefixes that must exist in the spec; the whole spec must pass
  if grep -q "could not load spec" <<<"$spec_out"; then echo "$spec_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, 0 failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out" | tail -n 40; return 1; }
  local c
  for c in "$@"; do
    # stylua may wrap `it(` and a long name over two lines: join lines before matching
    tr -d '\n\t' < "$spec" | grep -qF "it(\"$c" || { echo "the spec has no case starting \"$c\""; return 1; }
  done
}

check "AC1: land pushes one linear commit on top of origin/main, merges others first, retries a race, updates the main checkout" cases_pass \
  "land pushes one commit" "land brings the main checkout up" "land merges what others pushed" "land retries a lost race"
check "AC2: land carries only edits to draft backlog issue documents, status and design unchanged" cases_pass \
  "land refuses a change outside" "land refuses anything but edits to draft"
check "AC3: land refuses when the gate fails" cases_pass "land refuses when the gate fails"
check "AC4: land refuses outside a capture worktree, dirty, or with nothing to land" cases_pass "land refuses outside a capture worktree"
check "AC5: make-issue lands with tracker.sh land (no PR); the tracker skill names land" bash -c '
  m=.claude/skills/make-issue/SKILL.md; t=.claude/skills/tracker/SKILL.md
  step=$(grep -E "^6\. " "$m")
  grep -qF "tracker.sh land" <<<"$step" || { echo "make-issue step 6 does not run tracker.sh land"; exit 1; }
  ! grep -qiE "\bPR\b|pull request" <<<"$(sed "s/[Nn]o PR//; s/no pull request//" <<<"$step")" || { echo "make-issue step 6 still opens a PR"; exit 1; }
  sed -n "/^## Landing a change/,/^## /p" "$t" | grep -qF "tracker.sh land" || { echo "tracker skill: Landing a change"; exit 1; }
  grep -F "**The direct-push exception.**" "$t" | grep -qF "tracker.sh land" || { echo "tracker skill: the direct-push exception does not name tracker.sh land"; exit 1; }
  grep -qF "scripts/tracker.sh worktree" "$m" || { echo "make-issue: c0005 marker lost"; exit 1; }'

finish
