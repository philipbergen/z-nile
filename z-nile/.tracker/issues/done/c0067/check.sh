#!/usr/bin/env bash
# Acceptance checks for c0067. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0067 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0067"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# ready.spec is one end-to-end fixture: it runs once, and each check requires its own named cases to exist and pass.
spec="$A/ready.spec.luau"
spec_out=$(lune run tests/run -- "$spec" 2>&1)
cases_pass() { # $@: case-name prefixes that must exist in the spec and not appear in a FAIL line
  if grep -q "could not load spec" <<<"$spec_out"; then echo "$spec_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, 0 failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out" | tail -n 40; return 1; }
  local c
  for c in "$@"; do
    # stylua may wrap `it(` and a long name over two lines: join lines before matching
    tr -d '\n\t' < "$spec" | grep -qF "it(\"$c" || { echo "the spec has no case starting \"$c\""; return 1; }
  done
}

check "AC1: paths.rewrite moves only the listed ids state segments" lune run tests/run -- "$A/paths.spec.luau"
check "AC2: publish validates whole-directory moves; non-move rules unchanged" lune run tests/run -- "$A/publish-move.spec.luau"
check "AC3: ready refuses outside the main checkout, without origin, unprepared, dirty, blocked, unchecked, raftless" cases_pass \
  "ready refuses outside the main checkout" "ready refuses a raft that is not prepared" "ready refuses a dirty main checkout" \
  "ready refuses an unfinished dependency" "ready refuses a raft whose member has no check" "ready resolves an issue to its raft"
check "AC4: ready publishes one commit moving every file to active/, stamped, check.sh paths rewritten" cases_pass \
  "ready moves the raft and its members" "ready rewrites the moved check.sh paths"
check "AC5: the main checkout is pulled, prompt.md is written and ignored, no clipboard" cases_pass \
  "ready pulls the main checkout" "ready never calls pbcopy" "prompt.md embeds the workstreams plan"
check "AC6: ready on an active raft regenerates the prompt without a commit" cases_pass \
  "ready on an active raft regenerates"
check "AC7: start on a readied raft branches with an empty commit and moves nothing; a pre-ready worktree is told to sync" cases_pass \
  "start on a readied raft" "start in a worktree made before ready says to sync first"
check "AC8: the current raft is found by branch; emergent issues only on the raft's branch" cases_pass \
  "commit works on a raft branch" "new issue --raft needs the raft's branch" "done rewrites check.sh paths"
check "AC9: done rewrites check.sh paths to done/" cases_pass "done rewrites check.sh paths"
check "AC10: ready-raft replaces make-prompt in the skills, template and AGENTS.md; no clipboard; no banned phrases" bash -c '
  s=skills/z-ready/SKILL.md
  [ -f "$s" ] || { echo "no $s"; exit 1; }
  [ ! -e .claude/skills/make-prompt ] || { echo "make-prompt still exists"; exit 1; }
  grep -q "^name: ready-raft$" "$s" || { echo "ready-raft: name"; exit 1; }
  for k in "./zn ready" "prompt.md" "2. **Check readiness" "parallel:" "./zn worktree" "/launch-raft"; do
    grep -qF -- "$k" "$s" || { echo "ready-raft: missing $k"; exit 1; }
  done
  grep -Eq "zn sync([^ -]|$)" "$s" || { echo "ready-raft: no merging sync"; exit 1; }
  grep -qF "ready-raft/SKILL.md" ../AGENTS.md || { echo "AGENTS.md: ready-raft row"; exit 1; }
  t=skills/zz-rules/SKILL.md
  grep -qF "./zn ready" "$t" || grep -qE "^\| ready \|" "$t" || { echo "tracker skill: ready"; exit 1; }
  grep -qF "prompt.md" "$t" || { echo "tracker skill: prompt.md"; exit 1; }
  grep -qF "/ready-raft" skills/z-design/SKILL.md || { echo "ticket-prep: next step"; exit 1; }
  ! grep -qF "moves the items to \`active/\`" skills/zz-execute/SKILL.md || { echo "execute-raft: start still moves"; exit 1; }
  bad=$(grep -rnIi -e "pbcopy" -e "clipboard" .claude ./templates scripts ../AGENTS.md || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }
  # the 13 phrases c0005 AC5 bans
  bad=$(grep -rniF -e "git switch main" -e "Commit to main" -e "straight to main" -e "direct commits to main" \
    -e "to main as one commit" -e "runs on main before any PR" -e "root is on another branch" \
    -e "git diff main...HEAD" -e "ExitWorktree" -e "wrapping it in a placeholder raft" \
    -e "which gets a placeholder raft" -e "creates a placeholder raft" -e "wrap a single issue with" \
    skills ../pickman/skills ./templates ../AGENTS.md ../SETUP.md engine/main.luau || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'
check "AC12: the main checkout is swept of what moved items left behind; readied prompts are kept" cases_pass \
  "sync in the main checkout sweeps what a raft" "ready moves the raft and its members"
check "AC13: CI dispatched gate runs only the acceptance specs of the branch raft" bash -c '
  w=../.github/workflows/check.yml
  grep -qF "*/active/*/acceptance/*.spec.luau" "$w" || { echo "check.yml: the active acceptance glob is gone (c0001 pins it)"; exit 1; }
  grep -qF "./zn members" "$w" || { echo "check.yml: the dispatched step does not select the raft members"; exit 1; }
  grep -qF "GITHUB_REF_NAME" "$w" || { echo "check.yml: the raft is not taken from the dispatched ref"; exit 1; }'

finish
