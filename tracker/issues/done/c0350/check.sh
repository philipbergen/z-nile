#!/usr/bin/env bash
# Acceptance checks for c0350. SEQUESTERED: never edit during execution.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(git -C "$A" rev-parse --show-toplevel)/scripts/lib/ac.sh"
T=.claude/skills/tracker/SKILL.md
X=.claude/skills/execute-raft/SKILL.md
merging() { sed -n '/^## Merging/,/^## After merge/p' "$T"; }
phase6() { sed -n '/^## Phase 6/,/^## Stop/p' "$X"; }
phase4() { sed -n '/^## Phase 4/,/^## Phase 5/p' "$X"; }

ac1() { merging | grep -q 'gh pr merge' && merging | grep -q 'check.sh --full' && merging | grep -q 'green on the PR' && merging | grep -q 'Never use `--admin`'; }
ac2() { ! grep -qiE 'agents? (never|must not|do not|don.t) merge|human merges the PR' "$T" "$X"; }
ac5() { merging | grep -q 'CLEAN' && merging | grep -q 'headRefOid' && merging | grep -q 'SKIPPED' && merging | grep -q 'BLOCKED:'; }
ac6() { phase4 | grep -q "can't downgrade" && phase4 | grep -q 'c0360' && phase4 | grep -qE 'review-(003|NNN)\.md. contains any'; }
ac8() { phase4 | grep -q 'you refuted (rather than fixed) any high'; }
ac9() { merging | grep -q "body \$'" && merging | grep -q 'mergeCommit'; }
ac7() { sed -n '/^## Phase 5/,/^## Phase 6/p' "$X" | grep -q 'Ready to merge' && phase6 | grep -q 'merge commit sha' && phase6 | grep -q 'before. cleanup'; }
ac3() { merging | grep -q 'significant' && phase4 | grep -q 'significant' && phase4 | grep -q 'any \*\*high\*\* finding'; }
ac4() { phase6 | grep -q 'without waiting for a human'; }

check "AC1: Merging section has the conditions" ac1
check "AC2: no 'agents never merge'" ac2
check "AC3: only significant round-3 leftovers block" ac3
check "AC4: Phase 6 merges without a human" ac4
check "AC5: merge gate is explicit (CLEAN, head sha and gate check, BLOCKED after done)" ac5
check "AC6: interim answer is limited and points at c0360" ac6
check "AC7: final report comes after the merge" ac7
check "AC8: a refuted high triggers a re-review" ac8
check "AC9: real trailer and a merge sha command" ac9

finish
