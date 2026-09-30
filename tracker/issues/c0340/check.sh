#!/usr/bin/env bash
# Acceptance checks for c0340. SEQUESTERED: never edit during execution.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(git -C "$A" rev-parse --show-toplevel)/scripts/lib/ac.sh"
T=.claude/skills/tracker/SKILL.md
X=.claude/skills/execute-raft/SKILL.md
after() { sed -n '/^## After merge/,/^## /p' "$T"; }

ac1() { after | grep -q 'worktree remove' && after | grep -q 'branch -D' && after | grep -qi 'remote branch'; }
ac2() { after | grep -q 'fetch origin main:main' && after | grep -q 'ff-only'; }
ac3() { sed -n '/^## Phase 6/,/^## Stop/p' "$X" | grep -q 'After merge'; }

check "AC1: After merge removes worktree and local branch" ac1
check "AC2: root checkout on another branch is handled" ac2
check "AC3: execute-raft Phase 6 points at it" ac3

finish
