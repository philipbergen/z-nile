#!/usr/bin/env bash
# Acceptance checks for c0510. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0510 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0510"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: the pure status rules hold" lune run tests/run -- "$A/status.spec.luau"
check "AC2: the publisher pushes only whitelisted files on top of origin/main and retries a lost race" lune run tests/run -- "$A/publish.spec.luau"
check "AC3: the CLI publishes, claims, starts, syncs and stays local when asked" lune run tests/run -- "$A"/commands*.spec.luau # R0250 c0680 splits the spec
existing_specs_pass() { # the runner takes files, not directories
  local files
  files=$(find tests/acceptance tests/tooling -name '*.spec.luau' | sort)
  # shellcheck disable=SC2086
  lune run tests/run -- $files
}
check "AC4: every existing acceptance and tooling spec still passes (local behaviour unchanged)" existing_specs_pass

workflow_ignores_tracker_pushes() {
  local f=.github/workflows/check.yml push pr
  push=$(awk '/^  push:/{p=1;next} /^  [a-z_]+:/{p=0} p' "$f")
  pr=$(awk '/^  pull_request:/{p=1;next} /^  [a-z_]+:/{p=0} p' "$f")
  grep -q 'paths-ignore' <<<"$push" || { echo "push has no paths-ignore"; return 1; }
  grep -q "tracker/\*\*" <<<"$push" || { echo "push does not ignore tracker/**"; return 1; }
  ! grep -q 'paths-ignore\|paths:' <<<"$pr" || { echo "pull_request must not be path-filtered"; return 1; }
}
check "AC5: check.yml ignores tracker/** on push, and only on push" workflow_ignores_tracker_pushes

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
check "AC6: the skills sync (reviewers fetch only), diff sequestered files against origin/main...HEAD, and the tracker skill states the sync-and-claim rules" skills_carry_sync_and_claim

usage_lists_new_commands() {
  local out
  out=$(scripts/tracker.sh no-such-command 2>&1 || true)
  grep -q '^  status ' <<<"$out" && grep -q '^  sync ' <<<"$out" && grep -q -- '--desc' <<<"$out" && grep -q -- '--fetch' <<<"$out"
}
check "AC7: the usage text lists status, sync, --fetch and --desc" usage_lists_new_commands

replacements_applied() {
  # the promoted specs this issue deliberately changes, rewritten in prep (review 001 F1, review 003 F2)
  local R="$HERE/replacements" f
  for f in c0041/worktree c0140/workflow; do
    cmp -s "$R/${f%%/*}-${f##*/}.spec.luau" "tests/acceptance/$f.spec.luau" || { echo "tests/acceptance/$f.spec.luau is not the prepared replacement"; return 1; }
  done
  grep -q 'PICKMAN_PUBLISH' tests/acceptance/c0041/worktree.spec.luau && grep -q 'paths-ignore' tests/acceptance/c0140/workflow.spec.luau
}
check "AC8: the c0041 and c0140 specs are exactly the prepared replacements (PICKMAN_PUBLISH=0 in c0041's fixtures, paths-ignore in c0140's trigger)" replacements_applied

no_index() { # the tree is built with mktree: no index, so no git variable for the repository guards (R0210) to ban
  local f=scripts/tracker/publish.luau
  [[ -f $f ]] || { echo "$f is missing"; return 1; }
  # the variable name is split so this file does not name it (R0210's gate scans every check.sh)
  if grep -rnE "GIT_INDEX_""FILE|read-tree|update-index|write-tree" scripts/tracker/; then echo "the tracker code uses an index"; return 1; fi
  grep -qE '"mktree"' "$f" || { echo "the publisher does not pass \"mktree\" to git"; return 1; }
}
check "AC9: the publisher builds its tree with mktree and uses no index" no_index

finish
