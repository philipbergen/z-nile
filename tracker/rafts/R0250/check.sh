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
  ! grep -qF "launch" <<<"$u" || { echo "usage: launch (not even /launch-raft)"; exit 1; }'
check "RC5: the done check.sh files edited in prep, and c0070 (done order wording), pass" bash -c '
  for id in c0041 c0430 c0440 c0450 c0070; do
    bash "tracker/issues/done/$id/check.sh" >/dev/null 2>&1 || { echo "$id check.sh fails"; bash "tracker/issues/done/$id/check.sh" | grep FAIL; exit 1; }
  done'
check "RC6: c0510's replacement copies match and ready-raft syncs (c0510 AC6/AC8, targeted)" bash -c '
  R=tracker/issues/done/c0510/replacements
  cmp -s "$R/c0041-worktree.spec.luau" tests/acceptance/c0041/worktree.spec.luau || { echo "c0041 replacement differs"; exit 1; }
  cmp -s "$R/c0140-workflow.spec.luau" tests/acceptance/c0140/workflow.spec.luau || { echo "c0140 replacement differs"; exit 1; }
  grep -Eq "tracker\.sh sync([^ -]|$)" .claude/skills/ready-raft/SKILL.md || { echo "ready-raft: no merging sync"; exit 1; }'

# c0510's AC6, AC7 and AC9, copied verbatim (review 002 F5): this raft rewrites that skill text, USAGE and the publisher.
# c0510's whole check.sh is not run because its AC4 reruns every acceptance spec.
skills_carry_sync_and_claim() {
  local s merging='tracker\.sh sync([^ -]|$)'
  # the working skills run the merging form; reviewers, stream agents and metrics fetch only
  for s in tracker ticket-prep ready-raft execute-raft make-issue; do
    grep -Eq "$merging" ".claude/skills/$s/SKILL.md" || { echo "$s skill has no 'tracker.sh sync' (merging) step"; return 1; }
  done
  for s in review metrics; do
    grep -q 'tracker\.sh sync --fetch' ".claude/skills/$s/SKILL.md" || { echo "$s skill has no 'tracker.sh sync --fetch' step"; return 1; }
    ! grep -Eq "$merging" ".claude/skills/$s/SKILL.md" || { echo "$s skill still runs the merging 'tracker.sh sync'"; return 1; }
  done
  # the sequestration diff separates this branch's changes from what main brought in
  for s in review execute-raft; do
    grep -q 'origin/main\.\.\.HEAD -- .tracker/\*\*/check\.sh. .tracker/\*\*/acceptance/\*\*.' ".claude/skills/$s/SKILL.md" || { echo "$s skill's sequestration diff is not against origin/main...HEAD"; return 1; }
  done
  local t=.claude/skills/tracker/SKILL.md
  grep -q '^## Sync and claim' "$t" || { echo "tracker skill has no 'Sync and claim' section"; return 1; }
  grep -q 'PICKMAN_PUBLISH' "$t" || { echo "tracker skill does not document PICKMAN_PUBLISH"; return 1; }
  grep -q 'new -> preparing -> prepared -> active -> done' "$t" || { echo "tracker skill does not list the statuses"; return 1; }
  grep -q 'paths-ignore\|tracker-only' "$t" || { echo "tracker skill does not state the direct-push limit"; return 1; }
  grep -q 'status <R-id> preparing' "$t" || { echo "tracker skill does not say how an existing raft is claimed"; return 1; }
  grep -q 'status <R-id> prepared' .claude/skills/ticket-prep/SKILL.md || { echo "ticket-prep does not run status <R-id> prepared before the prep commit"; return 1; }
  grep -q 'Whose claim' "$t" || { echo "tracker skill does not say that claims are not owned"; return 1; }
}
usage_lists_new_commands() {
  local out
  out=$(scripts/tracker.sh no-such-command 2>&1 || true)
  grep -q '^  status ' <<<"$out" && grep -q '^  sync ' <<<"$out" && grep -q -- '--desc' <<<"$out" && grep -q -- '--fetch' <<<"$out"
}
no_index() { # the tree is built with mktree: no index, so no git variable for the repository guards (R0210) to ban
  local f=scripts/tracker/publish.luau
  [[ -f $f ]] || { echo "$f is missing"; return 1; }
  # the variable name is split so this file does not name it (R0210's gate scans every check.sh)
  if grep -rnE "GIT_INDEX_""FILE|read-tree|update-index|write-tree" scripts/tracker/; then echo "the tracker code uses an index"; return 1; fi
  grep -qE '"mktree"' "$f" || { echo "the publisher does not pass \"mktree\" to git"; return 1; }
}
check "RC7: c0510's sync-and-claim skill text, usage lines and index-free publisher still hold" bash -c "$(declare -f skills_carry_sync_and_claim usage_lists_new_commands no_index); skills_carry_sync_and_claim && usage_lists_new_commands && no_index"

finish
