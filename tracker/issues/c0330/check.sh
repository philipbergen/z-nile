#!/usr/bin/env bash
# Acceptance checks for c0330. SEQUESTERED: never edit during execution.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(git -C "$A" rev-parse --show-toplevel)/scripts/lib/ac.sh"
S=.claude/skills

phase4() { sed -n '/^## Phase 4/,/^## Phase 5/p' "$S/execute-raft/SKILL.md"; }
ac1() { phase4 | grep -q 'Review NNN started' && phase4 | grep -qi 'push'; }
ac2() { phase4 | grep -q 'tracker.sh commit -m "R0010: review-NNN"' && phase4 | grep -q 'finding count by severity'; }
ac3() { phase4 | grep -q 'Review NNN addressed'; }
ac4() { grep -q 'The PR is the visible record' "$S/tracker/SKILL.md" && grep -q '^## Visible record' "$S/review/SKILL.md"; }

check "AC1: review start is pushed and announced" ac1
check "AC2: review file is committed, pushed and summarized" ac2
check "AC3: answers are pushed and commented" ac3
check "AC4: tracker and review skills name the PR as the visible record" ac4

finish
