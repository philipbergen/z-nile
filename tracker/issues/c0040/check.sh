#!/usr/bin/env bash
# Acceptance checks for c0040. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
A="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/acceptance" # sequestered specs; see the testing skill
source "$(git -C "$A/.." rev-parse --show-toplevel)/scripts/lib/ac.sh"

# AC1-AC4 are cases of one end-to-end spec (shared fixture); each check runs it and requires
# its own named cases to pass by matching the runner's FAIL lines.
spec="$A/worktree.spec.luau"
cases_pass() { # $@: case-name substrings that must not appear in a FAIL line
  local out; out=$(lune run tests/run -- "$spec" 2>&1)
  for c in "$@"; do if grep -F "FAIL" <<<"$out" | grep -qF ":: $c"; then echo "$out"; return 1; fi; done
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$out" || { echo "$out"; return 1; }
}
check "AC1: raft-named worktree from origin/main, main checkout untouched" cases_pass \
  "worktree creates a raft-named" "worktree is idempotent" "main checkout stays on main"
check "AC2: start in worktree reuses branch, pushes, PR only for GitHub" cases_pass \
  "start inside the worktree" "non-GitHub origin"
check "AC3: worktree-prune removes finished rafts only" cases_pass "worktree-prune removes"
check "AC4: hooks act on the edited file's / session cwd's tree" cases_pass "post-edit hook" "stop hook"
check "AC5: skills and prompt make the worktree the first action" bash -c '
  grep -qF "cd \"\$(scripts/tracker.sh worktree" .claude/skills/execute-raft/SKILL.md &&
  grep -qF "scripts/tracker.sh worktree {{RAFT_ID}}" tracker/templates/prompt.md &&
  grep -qi "^#* *worktrees" .claude/skills/tracker/SKILL.md'
check "AC1-AC4: every case of the worktree spec passes" lune run tests/run -- "$spec"

finish
