#!/usr/bin/env bash
# Exit criteria for R0025. SEQUESTERED: never edit during execution.
# Runs the full repo gate, every member issue's check.sh, then raft-level end-to-end checks.
source "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/z-nile/lib/ac.sh"

check "RC0: repo gate passes (full)" ./check.sh --full
# every issue naming this raft, including emergent ones
for dir in $(../zn members R0025); do
  check "RC0: $(basename "$dir") acceptance checks pass" bash "$dir/check.sh"
done

check "RC0: acceptance specs will survive promotion into tests/" ../zn promote-check R0025

check "RC1: no make-prompt or ./zn launch remains in the skills, docs, templates or scripts" bash -c '
  bad=$(grep -rnF -e "make-prompt" -e "./zn launch" .claude ../AGENTS.md ../SETUP.md ./templates scripts || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'
check "RC2: AGENTS.md lists ready-raft, launch-raft and stop-raft, each with a matching SKILL.md" bash -c '
  for s in z-ready z-run z-stop; do
    grep -qF ".claude/skills/$s/SKILL.md" ../AGENTS.md || { echo "AGENTS.md: $s"; exit 1; }
    grep -q "^name: $s\$" "../.claude/skills/$s/SKILL.md" || { echo "$s: SKILL.md name"; exit 1; }
  done'
check "RC3: .gitignore ignores every readied raft's prompt.md" grep -qxF "/tracker/rafts/active/*/prompt.md" ../.gitignore
check "RC4: the usage text lists ready, stop and prompt <R-id> [--path], and no launch" bash -c '
  u=$(../zn 2>&1)
  for k in "ready <R-id|issue-id>" "stop <R-id>" "prompt <R-id> [--path]"; do
    grep -qF -- "$k" <<<"$u" || { echo "usage: missing $k"; exit 1; }
  done
  ! grep -qF "launch" <<<"$u" || { echo "usage: launch (not even /launch-raft)"; exit 1; }'
check "RC5: the done check.sh files edited in prep, and c0008 (done order wording), pass" bash -c '
  for id in c0005 c0045 c0046 c0047 c0008; do
    bash ".tracker/issues/done/$id/check.sh" >/dev/null 2>&1 || { echo "$id check.sh fails"; bash ".tracker/issues/done/$id/check.sh" | grep FAIL; exit 1; }
  done'
check "RC6: c0053's replacement copies match and ready-raft syncs (c0053 AC6/AC8, targeted)" bash -c '
  R=.tracker/issues/done/c0053/replacements
  cmp -s "$R/c0005-worktree.spec.luau" tests/acceptance/c0005/worktree.spec.luau || { echo "c0005 replacement differs"; exit 1; }
  cmp -s "$R/c0015-workflow.spec.luau" ../pickman/tests/acceptance/c0015/workflow.spec.luau || { echo "c0015 replacement differs"; exit 1; }
  grep -Eq "zn sync([^ -]|$)" skills/z-ready/SKILL.md || { echo "ready-raft: no merging sync"; exit 1; }'

# c0053's AC6, AC7 and AC9, copied verbatim (review 002 F5): this raft rewrites that skill text, USAGE and the publisher.
# c0053's whole check.sh is not run because its AC4 reruns every acceptance spec.
skills_carry_sync_and_claim() {
  local s merging='zn sync([^ -]|$)'
  # the working skills run the merging form; reviewers, stream agents and metrics fetch only
  for s in zz-rules z-design z-ready zz-execute z-ticket; do
    grep -Eq "$merging" "../.claude/skills/$s/SKILL.md" || { echo "$s skill has no './zn sync' (merging) step"; return 1; }
  done
  for s in zz-review zz-stats; do
    grep -q 'zn sync --fetch' "../.claude/skills/$s/SKILL.md" || { echo "$s skill has no './zn sync --fetch' step"; return 1; }
    ! grep -Eq "$merging" "../.claude/skills/$s/SKILL.md" || { echo "$s skill still runs the merging './zn sync'"; return 1; }
  done
  # the sequestration diff separates this branch's changes from what main brought in
  for s in zz-review zz-execute; do
    grep -q 'origin/main\.\.\.HEAD -- .tracker/\*\*/check\.sh. .tracker/\*\*/acceptance/\*\*.' "../.claude/skills/$s/SKILL.md" || { echo "$s skill's sequestration diff is not against origin/main...HEAD"; return 1; }
  done
  local t=skills/zz-rules/SKILL.md
  grep -q '^## Sync and claim' "$t" || { echo "tracker skill has no 'Sync and claim' section"; return 1; }
  grep -q 'PICKMAN_PUBLISH' "$t" || { echo "tracker skill does not document PICKMAN_PUBLISH"; return 1; }
  grep -q 'new -> preparing -> prepared -> active -> done' "$t" || { echo "tracker skill does not list the statuses"; return 1; }
  grep -q 'paths-ignore\|tracker-only' "$t" || { echo "tracker skill does not state the direct-push limit"; return 1; }
  grep -q 'status <R-id> preparing' "$t" || { echo "tracker skill does not say how an existing raft is claimed"; return 1; }
  grep -q 'status <R-id> prepared' skills/z-design/SKILL.md || { echo "ticket-prep does not run status <R-id> prepared before the prep commit"; return 1; }
  grep -q 'Whose claim' "$t" || { echo "tracker skill does not say that claims are not owned"; return 1; }
}
usage_lists_new_commands() {
  local out
  out=$(../zn no-such-command 2>&1 || true)
  grep -q '^  status ' <<<"$out" && grep -q '^  sync ' <<<"$out" && grep -q -- '--desc' <<<"$out" && grep -q -- '--fetch' <<<"$out"
}
no_index() { # the tree is built with mktree: no index, so no git variable for the repository guards (R0021) to ban
  local f=engine/publish.luau
  [[ -f $f ]] || { echo "$f is missing"; return 1; }
  # the variable name is split so this file does not name it (R0021's gate scans every check.sh)
  if grep -rnE "GIT_INDEX_""FILE|read-tree|update-index|write-tree" engine/; then echo "the tracker code uses an index"; return 1; fi
  grep -qE '"mktree"' "$f" || { echo "the publisher does not pass \"mktree\" to git"; return 1; }
}
check "RC7: c0053's sync-and-claim skill text, usage lines and index-free publisher still hold" bash -c "$(declare -f skills_carry_sync_and_claim usage_lists_new_commands no_index); skills_carry_sync_and_claim && usage_lists_new_commands && no_index"
check "RC8: no member acceptance spec names what R0021's gate scan bans, or runs a shell string" bash -c '
  # the banned list is read from the scan itself, so this file names none of it (review 005 F1)
  f=tests/tooling/repo-fence.spec.luau
  [ -f "$f" ] || { echo "$f is missing: R0021 is not merged"; exit 1; }
  names=$(sed -n "/^local NAMES = {/,/^}/p" "$f" | grep -o "\"[^\"]*\"" | tr -d "\"")
  [ -n "$names" ] || { echo "read no banned names from $f"; exit 1; }
  bad=""
  for d in $(../zn members R0025); do
    [ -d "$d/acceptance" ] || continue
    while IFS= read -r n; do
      hit=$(grep -rliF -- "$n" "$d/acceptance" || true)
      [ -z "$hit" ] || bad="$bad$hit names $n\n"
    done <<<"$names"
    hit=$(grep -rnE "\"(ba)?sh\", *\{ *\"-c\"|process\.create" "$d/acceptance" || true)
    [ -z "$hit" ] || bad="$bad$hit\n"
  done
  [ -z "$bad" ] || { printf "%b" "$bad"; exit 1; }'

finish
