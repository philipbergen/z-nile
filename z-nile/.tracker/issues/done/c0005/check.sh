#!/usr/bin/env bash
# Acceptance checks for c0005. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0005 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0005"

# AC1-AC4 and AC6 are cases of one end-to-end spec (shared fixture). It runs once; each check then
# requires its own named cases to have passed, and that the spec loaded at all.
spec="$A/worktree.spec.luau"
spec_out=$(lune run tests/run -- "$spec" 2>&1)
cases_pass() { # $@: case-name prefixes that must exist in the spec and not appear in a FAIL line
  if grep -q "could not load spec" <<<"$spec_out"; then echo "$spec_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out"; return 1; }
  local c
  for c in "$@"; do
    grep -qF "it(\"$c" "$spec" || { echo "the spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$spec_out" | grep -qF ":: $c"; then grep -F ":: $c" <<<"$spec_out"; return 1; fi
  done
}
all_cases_pass() {
  grep -q "could not load spec" <<<"$spec_out" && { echo "$spec_out"; return 1; }
  grep -Eq "^[0-9]+ passed, 0 failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out"; return 1; }
}

check "AC1: raft-named worktree from origin/main; resumes; refuses a taken branch; main untouched" cases_pass \
  "worktree creates a raft-named" "worktree is idempotent" "main checkout stays on main" \
  "worktree resumes an existing branch" "worktree refuses a branch checked out elsewhere" \
  "worktree branches from the fresh origin/main"
check "AC2: start in worktree reuses branch, pushes, draft PR only for GitHub" cases_pass \
  "start inside the worktree" "non-GitHub origin" "GitHub origin opens the draft PR"
check "AC3: worktree-prune removes finished rafts only, never forces" cases_pass \
  "worktree-prune removes" "worktree-prune keeps a raft" "worktree-prune lists a named" \
  "worktree-prune never forces" "worktree-prune run from inside" "worktree-prune removes a finished raft"
check "AC4: hooks act on the edited file's / session cwd's tree" cases_pass \
  "post-edit hook lints" "post-edit hook ignores" "stop hook gates the session" "stop hook gates the worktree root"
check "AC5: skills, prompt and AGENTS.md carry the worktree rule" bash -c '
  for f in zz-execute zz-rules z-ticket z-design z-ready; do
    grep -qF "./zn worktree" "../.claude/skills/$f/SKILL.md" || { echo "$f: no worktree command"; exit 1; }
  done
  grep -qF "./zn worktree {{RAFT_ID}}" templates/prompt.md || { echo "prompt template"; exit 1; }
  grep -qi "worktree" ../AGENTS.md || { echo "AGENTS.md"; exit 1; }
  grep -qiE "^#+ +worktrees" skills/zz-rules/SKILL.md || { echo "tracker: no Worktrees section"; exit 1; }
  grep -qiE "^#+ +landing a change" skills/zz-rules/SKILL.md || { echo "tracker: no Landing a change section"; exit 1; }
  for c in "worktree:\*" "worktree-prune:\*"; do
    grep -q "Bash(./zn $c)" ../.claude/settings.json || { echo "settings: missing $c"; exit 1; }
  done
  bad=$(grep -rniF -e "git switch main" -e "Commit to main" -e "straight to main" -e "direct commits to main" \
    -e "to main as one commit" -e "runs on main before any PR" -e "root is on another branch" \
    -e "git diff main...HEAD" -e "ExitWorktree" -e "wrapping it in a placeholder raft" \
    -e "which gets a placeholder raft" -e "creates a placeholder raft" -e "wrap a single issue with" \
    skills ../pickman/skills ./templates ../AGENTS.md ../SETUP.md engine/main.luau || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'
check "AC6: named worktrees; bad names, item ids, done rafts rejected; new/start refused in the main checkout" cases_pass \
  "worktree creates a named worktree" "worktree rejects bad names" "worktree refuses a done raft" \
  "start and new are refused" "renumber is refused" "prompt does not create" \
  "new issue works in a named worktree" "worktree recreates a worktree"
check "AC7: a duplicate id is an error; a shared number is a warning" cases_pass \
  "duplicate ids are reported" "a number shared by two prefixes"
check "AC1-AC4, AC6, AC7: every case of the worktree spec passes" all_cases_pass

finish
