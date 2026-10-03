#!/usr/bin/env bash
# Exit criteria for R0250. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/scripts/lib/ac.sh"

check "RC0: repo gate passes (full)" scripts/check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(scripts/tracker.sh members R0250); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" scripts/tracker.sh promote-check R0250

check "RC1: no make-prompt or tracker.sh launch remains in the skills, docs, templates or scripts" bash -c '
  bad=$(grep -rnF -e "make-prompt" -e "tracker.sh launch" .claude AGENTS.md SETUP.md tracker/templates scripts || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'
check "RC2: AGENTS.md lists ready-raft, launch-raft and stop-raft, each with a matching SKILL.md" bash -c '
  for s in ready-raft launch-raft stop-raft; do
    grep -qF ".claude/skills/$s/SKILL.md" AGENTS.md || { echo "AGENTS.md: $s"; exit 1; }
    grep -q "^name: $s\$" ".claude/skills/$s/SKILL.md" || { echo "$s: SKILL.md name"; exit 1; }
  done'
check "RC3: .gitignore ignores every readied raft's prompt.md" grep -qxF "/tracker/rafts/active/*/prompt.md" .gitignore
check "RC4: the usage text lists ready, stop and prompt <R-id> [--path], and no launch" bash -c '
  u=$(scripts/tracker.sh 2>&1)
  for k in "ready <R-id|issue-id>" "stop <R-id>" "prompt <R-id> [--path]"; do
    grep -qF -- "$k" <<<"$u" || { echo "usage: missing $k"; exit 1; }
  done
  ! grep -qw "launch" <<<"$u" || { echo "usage: launch"; exit 1; }'
check "RC5: the done check.sh files edited in prep pass (c0041, c0430, c0440, c0450)" bash -c '
  for id in c0041 c0430 c0440 c0450; do
    bash "tracker/issues/done/$id/check.sh" >/dev/null 2>&1 || { echo "$id check.sh fails"; bash "tracker/issues/done/$id/check.sh" | grep FAIL; exit 1; }
  done'
check "RC6: c0510's replacement copies match and ready-raft syncs (c0510 AC6/AC8, targeted)" bash -c '
  R=tracker/issues/done/c0510/replacements
  cmp -s "$R/c0041-worktree.spec.luau" tests/acceptance/c0041/worktree.spec.luau || { echo "c0041 replacement differs"; exit 1; }
  cmp -s "$R/c0140-workflow.spec.luau" tests/acceptance/c0140/workflow.spec.luau || { echo "c0140 replacement differs"; exit 1; }
  grep -Eq "tracker\.sh sync([^ -]|$)" .claude/skills/ready-raft/SKILL.md || { echo "ready-raft: no merging sync"; exit 1; }'

finish
