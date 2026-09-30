#!/usr/bin/env bash
# Acceptance checks for c0330. SEQUESTERED: never edit during execution.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(git -C "$A" rev-parse --show-toplevel)/scripts/lib/ac.sh"
S=.claude/skills
X="$S/execute-raft/SKILL.md"

# Text of one numbered Phase 4 step (the step's line plus its indented continuation lines).
step() {
  awk -v n="$1" '
    /^## Phase 4/ {p=1; next}
    /^## Phase 5/ {p=0}
    p && $0 ~ "^" n "\\. " {on=1; print; next}
    p && /^[0-9]+\. / {on=0}
    p && on {print}
  ' "$X"
}
has() { grep -q -- "$1"; }

ac1() { step 1 | has 'Review NNN started at' && step 1 | has 'tracker.sh commit' && step 1 | has 'comment'; }
ac2() { step 3 | has 'tracker.sh commit -m "R0010: review-NNN" --time 0' && step 3 | has 'finding count by severity'; }
ac3() { step 5 | has 'tracker.sh commit' && step 5 | has 'Review NNN addressed' && step 5 | has 'refute'; }
ac4() { grep -q '^## The PR is the visible record' "$S/tracker/SKILL.md" && grep -q 'BLOCKED' "$S/tracker/SKILL.md" && grep -q '^## Visible record' "$S/review/SKILL.md"; }
ac5() {
  sed -n '/^## Phase 1/,/^## Phase 2/p' "$X" | has 'PR comment' &&
    sed -n '/^## Phase 2/,/^## Phase 3/p' "$X" | has 'PR comment' &&
    sed -n '/^## Phase 3/,/^## Phase 4/p' "$X" | has 'PR comment'
}
ac6() { step 4 | has 'approve' && step 4 | has 'Phase 5'; }
ac7() { grep -q 'Dropped from review-' "$S/review/SKILL.md" && grep -q 'repeat of review-' "$S/review/SKILL.md"; }

check "AC1: review start is committed, pushed and announced (step 1)" ac1
check "AC2: review file is committed by the author, pushed and summarized (step 3)" ac2
check "AC3: fixes and answers are pushed and commented (step 5)" ac3
check "AC4: tracker and review skills name the PR as the visible record" ac4
check "AC5: phases 1-3 each post a PR comment" ac5
check "AC6: approve path skips the refute file" ac6
check "AC7: re-review format cannot trip tracker.sh done" ac7

finish
