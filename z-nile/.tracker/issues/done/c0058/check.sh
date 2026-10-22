#!/usr/bin/env bash
# Acceptance checks for c0058. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0058 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0058"

# Each spec's cases share one fixture, so each spec runs once (here, outside `check`: list mode refuses it);
# a check then requires its named cases to exist in the spec and not fail, and the spec to have loaded.
fence_out=$(lune run tests/run -- "$A/fence.spec.luau" 2>&1)
lock_out=$(lune run tests/run -- "$A/lock.spec.luau" 2>&1)
gate_out=$(lune run tests/run -- tests/tooling/repo-fence.spec.luau 2>&1)
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
fence() { cases_in "$A/fence.spec.luau" "$fence_out" "$@"; }
lock() { cases_in "$A/lock.spec.luau" "$lock_out" "$@"; }

check "AC1: git can't reach the repository from a fixture or .cache; inherited overrides are stripped; the guards reach every child, check.sh files included; a fake marker changes nothing" fence \
  "git in a fixture folder without a repository" "inherited repository overrides are stripped" \
  "the guards reach everything the run starts" "ac.sh gives check.sh files the same guards" \
  "a fake marker does not switch the guards off" "a marker leaked into another checkout below it is ignored" \
  "a run that can't be jailed and could write its repository refuses to start" \
  "a run inside a sandbox says it is not jailed again"
check "AC2: ref updates in the repository are refused except fetching; pushes into it are refused; specs get no GitHub credentials and push nowhere else" fence \
  "a ref update in the repository from inside a run is refused" "a push from a fixture into the repository is refused" \
  "a check.sh may fetch into refs/remotes, a spec may not" "specs get no GitHub credentials" \
  "the guard hooks hand a fixture's own hooks their arguments and input" \
  "a fixture's own git hooks still run under the guards" \
  "a check.sh started inside a spec run keeps the spec's limits"
check "AC3: the tripwire fails a run whose config, history, fixture refs or .cache worktrees changed, and ignores legitimate work; a fixture identity in the repository is refused" fence \
  "a repository whose git identity is a fixture's is refused" \
  "a run that changed remote or user config fails" "someone else's commit during a run" \
  "a run during which HEAD gained a fixture commit" "a run during which a fixture-written ref"
check "AC4: one run at a time per checkout: waits, takes over a dead lock, gives up on a live one, survives a killed top, no double takeover, nested runs don't lock" lock \
  "a second run in the same checkout waits" "a lock whose every process is gone is taken over" \
  "a lock held by a live process is waited for" "a run whose top process was killed keeps the lock" \
  "two runs waiting on one dead lock take it one at a time" "a run started from inside a run does not wait" \
  "a takeover left by a waiter that died before claiming it is cleared"
check "AC5: the runner's exit codes are unchanged (failures, a bad --jobs, list mode)" fence \
  "a failing case still fails the run" "a bad --jobs value still exits 2 through the guard" \
  "list mode is still refused before anything else"
gate() {
  fence "the gate spec fails on a spec, script or identity that would bypass a guard" || return 1
  cases_in tests/tooling/repo-fence.spec.luau "$gate_out" "this run is guarded for this checkout" \
    "git finds no repository in .cache" "every git this run starts refuses ref updates" \
    "on macOS this run can write nothing in the checkout outside .cache" "specs have no GitHub credentials" \
    "no spec, check.sh or script switches a guard off" "every fixture commits as <name>@example.invalid" || return 1
  grep -Eq "^7 passed, 0 failed, 1 spec files$" <<<"$gate_out" || { echo "$gate_out" | tail -5; return 1; }
}
check "AC6: the gate spec proves the guards are on, the jail included, and catches a planted bypass" gate
overrides() {
  local f=tests/acceptance/c0034/locator.spec.luau
  if grep -n "./zn" "$f" | grep -q "cwd = root"; then echo "$f still runs ./zn in the real repository"; return 1; fi
  lune run tests/run -- "$f" tests/acceptance/c0005/worktree.spec.luau tests/acceptance/c0044/naming.spec.luau \
    tests/acceptance/c0045/workstreams.spec.luau tests/acceptance/c0046/launch.spec.luau tests/tooling/worktree-fetch.spec.luau
}
check "AC7: the overridden specs (c0034 in a fixture, five without their own git config) still pass" overrides
docs() {
  local s=../.claude/skills t=../.claude/skills/testing/SKILL.md
  grep -qF "No check may ever change the real repository" ../AGENTS.md || { echo "AGENTS.md lacks the rule"; return 1; }
  grep -qF "## Specs never touch the real repository" "$t" || { echo "testing skill lacks its section"; return 1; }
  for p in "Enforced at run time" "Caught only by review" "Allowed writers" "If the tripwire fires" "Jail" '$TMPDIR'; do
    grep -qF "$p" "$t" || { echo "testing skill section lacks: $p"; return 1; }
  done
  if grep -qF "Run one suite per worktree at a time" "$t"; then echo "the Speed section still has the manual one-suite rule"; return 1; fi
  [[ $(grep "Repository safety" $s/review/SKILL.md | grep -c "high") -eq 2 ]] || { echo "review: Repository safety, high, in design and code mode"; return 1; }
  grep -qF "REPOSITORY CHANGED" $s/execute-raft/SKILL.md || { echo "execute-raft lacks the stop condition"; return 1; }
  grep -qF "never change the real repository" $s/ticket-prep/SKILL.md || { echo "ticket-prep lacks the rule"; return 1; }
  grep -qF '$TMPDIR' $s/ticket-prep/SKILL.md || { echo "ticket-prep: run acceptance specs against unguarded code only in a clone under $TMPDIR"; return 1; }
}
check "AC8: AGENTS.md and the testing, review, execute-raft and ticket-prep skills state the rule, what is enforced (the jail included) and what only review catches" docs

unsandboxed() { # AC9 and AC10 build sandboxes of their own, which macOS can't do from inside another one
  sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null ||
    { echo "this check runs sandboxes of its own: run it outside the sandbox you are in"; return 1; }
}
make_copy() { # $1: the copy; a copy of the runner and guards, plus a spec that tries to write this checkout
  local copy=$1 real req="req""uire" # keeps literal require text out of this file (graph scanner)
  real=$(pwd -P)
  rm -rf "$copy" && mkdir -p "$copy/z-nile/lib" "$copy/tests/probe"
  cp -R tests/run.luau tests/lib "$copy/tests/" && cp -R lib/fence.sh lib/git-hooks "$copy/z-nile/lib/"
  cp .luaurc ../rokit.toml "$copy/"
  cat >"$copy/tests/probe/chain.spec.luau" <<SPEC
--!strict
local fs = $req("@lune/fs")
local t = $req("@tests/lib/t")
return t.spec("chain", function(it)
	it("probe", function()
		local path = "$real/.pickman-chain-probe"
		local ok = pcall(fs.writeFile, path, "")
		if ok then
			pcall(fs.removeFile, path) -- harmless: an untracked file, removed at once
		end
		t.expect(ok).toBe(false)
	end)
end)
SPEC
}
chain() { # a copy of the tree under .cache runs its own gate (c0049's pattern): its jail must cover this checkout too
  if [[ $(uname) != Darwin ]]; then echo "no jail off macOS (environment guards only)"; return 0; fi
  unsandboxed || return 1
  local copy="$PWD/.cache/c0058-chain" out rc
  make_copy "$copy"
  out=$(cd "$copy" && lune run tests/run -- tests/probe/chain.spec.luau 2>&1); rc=$?
  rm -rf "$copy"
  echo "$out" | tail -5
  [[ $rc -eq 0 ]] && grep -Eq "^1 passed, 0 failed, 1 spec files$" <<<"$out"
}
check "AC9: a copy of the tree under .cache runs its specs in a jail that also covers this checkout" chain
refused() { # $1: what; $2: output; $3: exit code; a refusal before any spec, with no lock left behind
  if [[ $3 -ne 1 ]] || ! grep -qF "cannot jail this run" <<<"$2" || grep -q " passed, " <<<"$2"; then
    echo "$1: expected a refusal before any spec (exit $3):"; echo "$2" | tail -3; return 1
  fi
}
outer() { # inside another sandbox that would let specs write this checkout, a run refuses, before any spec
  if [[ $(uname) != Darwin ]]; then echo "no jail off macOS (environment guards only)"; return 0; fi
  unsandboxed || return 1
  local open='(version 1)(allow default)' out rc copy="$PWD/.cache/c0058-outer"
  out=$(sandbox-exec -p "$open" lune run tests/run -- tests/tooling/repo-fence.spec.luau 2>&1); rc=$?
  refused "this checkout" "$out" $rc || return 1
  # a ceiling that holds an ancestor of this checkout, as a prompt speed-up might, proves nothing
  out=$(GIT_CEILING_DIRECTORIES="$(dirname "$(pwd -P)")" sandbox-exec -p "$open" lune run tests/run -- tests/tooling/repo-fence.spec.luau 2>&1); rc=$?
  refused "an ancestor in the ceiling" "$out" $rc || return 1
  # a copy under .cache started from a check.sh: this checkout is writable there, so the copy is no fixture
  make_copy "$copy"
  out=$(cd "$copy" && sandbox-exec -p "$open" lune run tests/run -- tests/probe/chain.spec.luau 2>&1); rc=$?
  rm -rf "$copy"
  refused "a copy under .cache" "$out" $rc || return 1
  [[ ! -d .cache/tests-run.lock ]] || { echo "a refused run left its lock"; return 1; }
}
check "AC10: inside another sandbox that lets specs write this checkout, a run refuses before any spec runs (this checkout, an ancestor in the ceiling, a copy under .cache)" outer

finish
