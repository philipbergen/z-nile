#!/usr/bin/env bash
# Acceptance checks for c0040. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance" # sequestered specs; see the testing skill
source "$(git -C "$(dirname "$A")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

R="$(git -C "$(dirname "$A")" rev-parse --show-toplevel)/.claude/skills"
check "AC1: execute-raft code reviewer runs on the strongest model" grep -qi "reviewer.*opus" "$R/execute-raft/SKILL.md"
check "AC2: ticket-prep design reviewer runs on the strongest model" grep -qi "reviewer.*opus" "$R/ticket-prep/SKILL.md"

finish
