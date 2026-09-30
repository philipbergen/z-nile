#!/usr/bin/env bash
# Acceptance checks for c0430. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance" # sequestered specs; see the testing skill
source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"

# AC1-AC4 are cases of one end-to-end spec (shared fixture). It runs once; each check then requires
# its own named cases to exist in the spec and not fail, and that the spec loaded at all.
spec="$A/workstreams.spec.luau"
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

check "AC1: the plan: waves, overlaps, no-modules warning, parallel line, cycle and unknown raft errors" cases_pass \
  "workstreams orders waves" "a single-issue raft is sequential" "an issue without touched modules" \
  "a dependency cycle and an unknown raft"
check "AC2: worktree --from bases on the ref; unknown ref and raft id rejected" cases_pass \
  "worktree --from bases" "worktree --from rejects"
check "AC3: stream review files are not review rounds" cases_pass "stream review files are not review rounds"
check "AC4: the prompt embeds the plan" cases_pass "prompt embeds the workstreams plan"
check "AC5: skills and template carry the parallel protocol" bash -c '
  e=.claude/skills/execute-raft/SKILL.md
  for k in "Phase 2B" "tracker.sh workstreams" "--from" "stream-review" "git merge --squash" "model: \"sonnet\"" "model: \"opus\""; do
    grep -qF -- "$k" "$e" || { echo "execute-raft: missing $k"; exit 1; }
  done
  grep -qiE "^#+ +stream mode" .claude/skills/review/SKILL.md || { echo "review: no Stream mode section"; exit 1; }
  grep -qF "tracker.sh workstreams" .claude/skills/tracker/SKILL.md || { echo "tracker skill: workstreams"; exit 1; }
  grep -qF -- "--from" .claude/skills/tracker/SKILL.md || { echo "tracker skill: --from"; exit 1; }
  grep -qF "parallel:" .claude/skills/make-prompt/SKILL.md || { echo "make-prompt: parallel line"; exit 1; }
  grep -qF "## Workstreams plan" tracker/templates/prompt.md || { echo "prompt template: plan section"; exit 1; }
  grep -qF "{{WORKSTREAMS}}" tracker/templates/prompt.md || { echo "prompt template: variable"; exit 1; }'
check "AC1-AC4: every case of the workstreams spec passes" all_cases_pass

finish
