#!/usr/bin/env bash
# Acceptance checks for c0046. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0046 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0046"

# AC5 is a case of one end-to-end spec (shared fixture). It runs once; each check then requires
# its own named cases to exist in the spec and not fail, and that the spec loaded at all.
spec="$A/launch.spec.luau"
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
all_cases_pass() {
  grep -q "could not load spec" <<<"$spec_out" && { echo "$spec_out"; return 1; }
  grep -Eq "^[0-9]+ passed, 0 failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out"; return 1; }
}

# AC1-AC4 (the launch command) were removed with the command in R0025 (c0069)
check "AC5: worktree-prune warns about worktrees outside .worktree/" cases_pass \
  "worktree-prune warns about a worktree outside"
check "AC6: the skills state the inside-the-repo rule; no sibling or .worktrees/ path" bash -c '
  t=../.claude/skills/tracker/SKILL.md
  grep -qF ".worktree/" "$t" || { echo "tracker skill: .worktree/"; exit 1; }
  grep -qiE "never outside" "$t" || { echo "tracker skill: no \"never outside\" rule"; exit 1; }
  grep -qF ".worktree/" templates/prompt.md || { echo "prompt template: .worktree/"; exit 1; }
  # the c0005 AC5 markers must survive: done reruns every member check.sh
  for f in execute-raft tracker make-issue ticket-prep ready-raft; do
    grep -qF "./zn worktree" "../.claude/skills/$f/SKILL.md" || { echo "$f: c0005 marker lost"; exit 1; }
  done
  grep -qF "./zn worktree {{RAFT_ID}}" templates/prompt.md || { echo "prompt template: c0005 marker lost"; exit 1; }
  bad=$(grep -rnE -e "\.worktrees/" -e "\.\./pickman" ../.claude/skills ./templates ../SETUP.md ../AGENTS.md || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'
check "AC5: every case of the launch spec passes" all_cases_pass

finish
