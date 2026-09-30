#!/usr/bin/env bash
# Acceptance checks for c0440. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance" # sequestered specs; see the testing skill
source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"

# AC1-AC5 are cases of one end-to-end spec (shared fixture). It runs once; each check then requires
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

check "AC1: launch runs the command in the target's worktree, creating or reusing it" cases_pass \
  "launch runs the command inside"
check "AC2: arguments after -- pass through untouched; the default command is claude" cases_pass \
  "launch defaults to claude"
check "AC3: launch returns the exit code and reports a command that can't start" cases_pass \
  "launch returns the command's exit code"
check "AC4: an invalid target starts nothing" cases_pass "launch rejects an unknown target"
check "AC5: worktree-prune warns about worktrees outside .worktree/" cases_pass \
  "worktree-prune warns about a worktree outside"
check "AC6: the skills state the inside-the-repo rule and the launch line; no sibling or .worktrees/ path" bash -c '
  t=.claude/skills/tracker/SKILL.md
  grep -qF "scripts/tracker.sh launch" "$t" || { echo "tracker skill: launch"; exit 1; }
  grep -qF ".worktree/" "$t" || { echo "tracker skill: .worktree/"; exit 1; }
  grep -qiE "never outside" "$t" || { echo "tracker skill: no \"never outside\" rule"; exit 1; }
  for f in .claude/skills/make-prompt/SKILL.md SETUP.md AGENTS.md; do
    grep -qF "scripts/tracker.sh launch" "$f" || { echo "$f: launch line"; exit 1; }
  done
  grep -qF ".worktree/" tracker/templates/prompt.md || { echo "prompt template: .worktree/"; exit 1; }
  bad=$(grep -rnE -e "\.worktrees/" -e "\.\./pickman" .claude/skills tracker/templates SETUP.md AGENTS.md || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'
check "AC1-AC5: every case of the launch spec passes" all_cases_pass

finish
