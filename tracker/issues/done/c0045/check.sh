#!/usr/bin/env bash
# Acceptance checks for c0045. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0045 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0045"

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
  "a dependency cycle and an unknown raft" "waves are one more than the latest" "the latest wave in the after set" "overlap compares whole path"
check "AC2: worktree --from bases on the ref; unknown ref and raft id rejected" cases_pass \
  "worktree --from bases" "worktree --from rejects"
check "AC3: stream review files are not review rounds" cases_pass "stream review files are not review rounds"
# AC4 (the prompt embeds the plan, or its error) moved to c0067's ready.spec in R0025: prompt is now a reader
check "AC5: tracker.sh commit refuses while merge conflicts are unresolved" cases_pass "tracker.sh commit refuses"
check "AC6: skills and template carry the parallel protocol" bash -c '
  e=.claude/skills/execute-raft/SKILL.md
  for k in "Phase 2B" "tracker.sh workstreams" "--from" "stream-review" "git merge --squash" "model: \"sonnet\"" "model: \"opus\""; do
    grep -qF -- "$k" "$e" || { echo "execute-raft: missing $k"; exit 1; }
  done
  grep -qiE "^#+ +stream mode" .claude/skills/review/SKILL.md || { echo "review: no Stream mode section"; exit 1; }
  grep -qF "tracker.sh workstreams" .claude/skills/tracker/SKILL.md || { echo "tracker skill: workstreams"; exit 1; }
  grep -qF -- "--from" .claude/skills/tracker/SKILL.md || { echo "tracker skill: --from"; exit 1; }
  grep -qF "parallel:" .claude/skills/ready-raft/SKILL.md || { echo "ready-raft: parallel line"; exit 1; }
  grep -qF "## Workstreams plan" tracker/templates/prompt.md || { echo "prompt template: plan section"; exit 1; }
  grep -qF "{{WORKSTREAMS}}" tracker/templates/prompt.md || { echo "prompt template: variable"; exit 1; }
  grep -qF "stream branches are committed with plain git" tracker/templates/prompt.md || { echo "prompt template: hard rule 2"; exit 1; }
  grep -qF "One raft branch and one PR" tracker/templates/prompt.md || { echo "prompt template: hard rule 2 (one raft branch)"; exit 1; }
  grep -qF "Follow the \`execute-raft\` skill" tracker/templates/prompt.md || { echo "prompt template: hard rule 1 is gone"; exit 1; }'
check "AC1-AC5: every case of the workstreams spec passes" all_cases_pass

finish
