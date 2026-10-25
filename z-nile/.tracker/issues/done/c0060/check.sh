#!/usr/bin/env bash
# Acceptance checks for c0060. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0060 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0060"

spec="$A/fixture.spec.luau"
# The spec's cases share one fixture, so it runs once (here, outside `check`: list mode refuses it); each
# check then requires its named cases to exist in the spec and not fail, and the spec to have loaded.
spec_out=$(lune run tests/run -- "$spec" 2>&1)
cases_pass() { # $@: case-name prefixes that must exist in the spec and not appear in a FAIL line
  if grep -q "could not load spec" <<<"$spec_out"; then echo "$spec_out"; return 1; fi
  grep -Eq "^[0-9]+ passed, [0-9]+ failed, 1 spec files$" <<<"$spec_out" || { echo "$spec_out"; return 1; }
  local c
  for c in "$@"; do
    tr -d "\n\t" < "$spec" | grep -qF "it(\"$c" || { echo "the spec has no case starting \"$c\""; return 1; }
    if grep -F "FAIL" <<<"$spec_out" | grep -qF ":: $c"; then grep -F -A3 ":: $c" <<<"$spec_out"; return 1; fi
  done
}

check "AC1: the fixture helper runs commands only in a fixture repository, refusing anything else before it runs, and passes env and stdin" cases_pass \
  "a fixture repository, a worktree of it and a bare fixture are accepted" \
  "a folder under .cache without its own repository is refused" "a subfolder of a fixture is refused" \
  "the real checkout is refused" "a repository outside any .cache folder is refused" \
  "git raises with git's own output" "exec passes the environment and standard input" \
  "a repository under another .cache folder than this run's is refused" \
  "git options or variables that point at another repository are refused"
check "AC2: the twelve older fixture specs run git and ./zn only through the helper (self-tested scan)" \
  lune run tests/run -- "$A/retrofit.spec.luau"
TWELVE=(tests/acceptance/c0001/tracker-lifecycle.spec.luau tests/acceptance/c0005/worktree.spec.luau
  tests/acceptance/c0006/clone.spec.luau tests/acceptance/c0007/changed.spec.luau tests/acceptance/c0008/done-order.spec.luau
  tests/acceptance/c0034/locator.spec.luau tests/acceptance/c0038/deferred.spec.luau tests/acceptance/c0044/naming.spec.luau
  tests/acceptance/c0045/workstreams.spec.luau tests/acceptance/c0046/launch.spec.luau
  tests/acceptance/c0050/start-depends.spec.luau tests/tooling/worktree-fetch.spec.luau)
check "AC3: the twelve specs pass under the guards" lune run tests/run -- "${TWELVE[@]}"
unguarded() { # the twelve, against the runner without its guards, in a clone outside every repository
  local tmp clone snap before after out rc
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/c0060.XXXXXX") || return 1
  clone="$tmp/repo"
  git clone -q --no-hardlinks "$PWD" "$clone" || return 1
  # no way back: an escaped push or fetch in the clone must not reach this checkout
  git -C "$clone" remote remove origin || return 1
  # the working tree as it is, uncommitted edits included
  tar -cf - --exclude=./.git --exclude=./.cache --exclude=./.worktree . | (cd "$clone" && tar -xf -) || return 1
  perl -0pi -e 's/\nrequire\("\.\/lib\/fence"\)\.enter\(\)\n/\n/' "$clone/tests/run.luau"
  if grep -q 'lib/fence' "$clone/tests/run.luau"; then echo "could not remove the runner's guard call"; return 1; fi
  snap='git config --local --list | sort; git for-each-ref --format="%(refname) %(objectname)"; git rev-parse HEAD; git worktree list --porcelain | grep "^worktree"; git status --porcelain | sort'
  before=$(cd "$clone" && bash -c "$snap")
  # no credentials: nothing in the clone may reach GitHub (it has no origin either)
  out=$(cd "$clone" && env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN -u SSH_AUTH_SOCK \
    GIT_TERMINAL_PROMPT=0 lune run tests/run -- "${TWELVE[@]}" 2>&1); rc=$?
  after=$(cd "$clone" && bash -c "$snap")
  rm -rf "$tmp"
  echo "$out" | tail -3
  [[ $rc -eq 0 ]] || { echo "the specs failed unguarded"; return 1; }
  [[ $before == "$after" ]] || { echo "the clone's repository changed:"; diff <(echo "$before") <(echo "$after"); return 1; }
}
check "AC4: unguarded, in a clone under TMPDIR, the twelve specs pass and leave the clone's repository unchanged" unguarded
check "AC5: the testing skill states the fixture rule and names the specs not yet converted" bash -c '
  s=../.claude/skills/testing/SKILL.md
  grep -qF "@tests/lib/fixture" "$s" || { echo "the testing skill does not name @tests/lib/fixture"; exit 1; }
  grep -qF "c0053" "$s" || { echo "the rule does not name the specs not yet converted"; exit 1; }
  if grep -qF "in new and edited specs" "$s"; then echo "the rule still says new and edited specs only"; exit 1; fi
  if grep -qF "retrofitting them is a follow-up" "$s"; then echo "the follow-up sentence is still there"; exit 1; fi'

finish
