#!/usr/bin/env bash
# Acceptance checks for c0070. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0070 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0070"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
spec="$A/board-refresh.spec.luau"
spec_out=$(lune run tests/run -- "$spec" 2>&1)
cases_pass() { # $@: case-name prefixes that must exist in the spec; the whole spec must pass
  if grep -q "could not load spec" <<<"$spec_out"; then echo "$spec_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, 0 failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out" | tail -n 40; return 1; }
  local c
  for c in "$@"; do
    # stylua may wrap `it(` and a long name over two lines: join lines before matching
    tr -d '\n\t' < "$spec" | grep -qF "it(\"$c" || { echo "the spec has no case starting \"$c\""; return 1; }
  done
}

check "AC1: every push to origin/main brings the main checkout up and rebuilds its board; no browser" cases_pass \
  "new issue in a worktree brings the main checkout" "the refreshed board equals a fresh build" \
  "status and new raft refresh the board" "ready and stop refresh the board" "no browser is opened"
check "AC2: sync in the main checkout rebuilds the board" cases_pass "sync in the main checkout rebuilds the board"
check "AC3: a failed refresh only warns; no refresh without publishing" cases_pass \
  "a main checkout off main only warns" "no refresh without publishing"
check "AC4: every publish.commit in main.luau goes through published()" bash -c '
  m=z-nile/engine/main.luau
  grep -qF "local function published(" "$m" || { echo "no published()"; exit 1; }
  n=$(grep -c "publish\.commit(" "$m")
  [ "$n" -ge 5 ] || { echo "only $n publish.commit calls: expected new (2), status, start, ready, stop"; exit 1; }
  bad=$(grep -n "publish\.commit(" "$m" | grep -vF "published(publish.commit(" || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'
check "AC5: Landing a change, step 4, syncs the root with ./zn; no skill pulls the root by hand after a merge" bash -c '
  t=.claude/skills/tracker/SKILL.md
  step=$(grep -E "^4\. \*\*After the merge" "$t")
  [ -n "$step" ] || { echo "no Landing step 4"; exit 1; }
  grep -qE "zn\"? sync" <<<"$step" || { echo "step 4 does not run ./zn sync"; exit 1; }
  bad=$(grep -rnF "git -C <root> pull --ff-only" .claude/skills || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'

finish
