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
ac2() { ! grep -q 'Agents never merge' "$T"; }
ac3() { merging | grep -q 'significant' && phase4 | grep -q 'significant' && phase4 | grep -q 'unresolved \*\*high\*\*'; }
ac4() { phase6 | grep -q 'without waiting for a human'; }

check "AC1: Merging section has the conditions" ac1
check "AC2: no 'agents never merge'" ac2
check "AC3: only significant round-3 leftovers block" ac3
check "AC4: Phase 6 merges without a human" ac4

finish
