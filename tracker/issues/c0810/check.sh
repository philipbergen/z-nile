#!/usr/bin/env bash
# Acceptance checks for c0810. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0810 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0810"

# The spec's cases share one setup, so it runs once (here, outside `check`: list mode refuses it); a check then
# requires its named cases to exist in the spec and not fail, and the spec to have loaded.
shell_out=$(lune run tests/run -- "$A/shell-git.spec.luau" 2>&1)
cases_in() { # $1: spec file, $2: its output, $3...: case-name prefixes that must exist and not fail
  local spec=$1 out=$2 c; shift 2
  [[ -f $spec ]] || { echo "missing $spec"; return 1; }
  if grep -q "could not load spec" <<<"$out"; then echo "$out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$out" || { echo "$out" | tail -20; return 1; }
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "$spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$out" | grep -qF ":: $c"; then grep -F -A3 ":: $c" <<<"$out"; return 1; fi
  done
}
shell_git() { cases_in "$A/shell-git.spec.luau" "$shell_out" "$@"; }

check "AC1: a command run through the helper can't run git outside .cache, by cd, options or variables" shell_git \
  "a shell command that changes to the real checkout cannot run git there" \
  "git -C, --git-dir, --work-tree and core.worktree can't reach the real checkout" \
  "a repository variable set inside the command is refused" "a script run through the helper gets the same fence" \
  "a command outside any repository is refused" \
  "a fixture whose own config points core.worktree at the real checkout is refused" \
  "core.worktree set through the environment doesn't reach the real checkout" \
  "init, clone and worktree add can't make or retarget a repository outside .cache" \
  "a .git symlink into a repository outside .cache is refused"
check "AC2: git in fixtures, init and clone still work, and fixture.git is unchanged" shell_git \
  "git in the fixture and in another fixture under .cache still works" "the helper's own git calls are unchanged" \
  "git options and variables pointing at another fixture under .cache work"
TWELVE=(tests/acceptance/c0010/tracker-lifecycle.spec.luau tests/acceptance/c0041/worktree.spec.luau
  tests/acceptance/c0050/clone.spec.luau tests/acceptance/c0060/changed.spec.luau tests/acceptance/c0070/done-order.spec.luau
  tests/acceptance/c0330/locator.spec.luau tests/acceptance/c0360/deferred.spec.luau tests/acceptance/c0420/naming.spec.luau
  tests/acceptance/c0430/workstreams.spec.luau tests/acceptance/c0440/launch.spec.luau
  tests/acceptance/c0480/start-depends.spec.luau tests/tooling/worktree-fetch.spec.luau)
check "AC3: the twelve converted specs and the helper's own specs pass" lune run tests/run -- "${TWELVE[@]}" \
  tests/acceptance/c0660/fixture.spec.luau tests/acceptance/c0660/retrofit.spec.luau tests/tooling/fixture-elsewhere.spec.luau

finish
