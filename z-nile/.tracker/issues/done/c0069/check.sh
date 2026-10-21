#!/usr/bin/env bash
# Acceptance checks for c0069. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0069 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0069"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
spec="$A/prompt.spec.luau"
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

check "AC1: prompt refuses a raft that is not readied, naming /ready-raft" cases_pass "prompt refuses a raft that is not readied"
check "AC2: prompt prints prompt.md exactly (or --path), from anywhere, writing nothing" cases_pass \
  "prompt prints the readied raft's prompt.md exactly" "prompt --path prints" "prompt writes nothing"
check "AC3: prompt refuses a missing prompt.md and a non-raft id" cases_pass \
  "prompt refuses a missing prompt.md" "prompt takes only a raft id"
check "AC4: ./zn launch is gone" cases_pass "./zn launch is gone"
check "AC5: the launch-raft skill; docs point to /launch-raft; no ./zn launch anywhere" bash -c '
  s=.claude/skills/launch-raft/SKILL.md
  [ -f "$s" ] || { echo "no $s"; exit 1; }
  grep -q "^name: launch-raft$" "$s" || { echo "launch-raft: name"; exit 1; }
  for k in "./zn prompt" "--path" "Read" "./zn worktree" "/ready-raft"; do
    grep -qF -- "$k" "$s" || { echo "launch-raft: missing $k"; exit 1; }
  done
  for f in AGENTS.md SETUP.md .claude/skills/tracker/SKILL.md .claude/skills/ready-raft/SKILL.md; do
    grep -qF "/launch-raft" "$f" || { echo "$f: /launch-raft"; exit 1; }
  done
  grep -qF "launch-raft/SKILL.md" AGENTS.md || { echo "AGENTS.md: launch-raft row"; exit 1; }
  bad=$(grep -rnF "./zn launch" .claude AGENTS.md SETUP.md z-nile/templates scripts || true)
  [ -z "$bad" ] || { echo "$bad"; exit 1; }'
check "AC6: the overridden c0046, c0045 and c0005 specs pass; c0053's replacement copy still matches" bash -c '
  lune run tests/run -- tests/acceptance/c0046/launch.spec.luau || exit 1
  ! grep -qF "it(\"launch" tests/acceptance/c0046/launch.spec.luau || { echo "c0046: launch cases remain"; exit 1; }
  grep -qF "it(\"worktree-prune warns about a worktree outside" tests/acceptance/c0046/launch.spec.luau || { echo "c0046: prune case lost"; exit 1; }
  ! grep -qF "./zn launch" z-nile/.tracker/issues/done/c0046/check.sh || { echo "c0046 check.sh: launch"; exit 1; }
  lune run tests/run -- tests/acceptance/c0045/workstreams.spec.luau || exit 1
  ! grep -qF "it(\"prompt embeds" tests/acceptance/c0045/workstreams.spec.luau || { echo "c0045: prompt cases remain"; exit 1; }
  grep -qF "it(\"prompt does not create" tests/acceptance/c0005/worktree.spec.luau || { echo "c0005: prompt case renamed"; exit 1; }
  test -f z-nile/.tracker/issues/done/c0053/replacements/c0005-worktree.spec.luau || { echo "c0053 replacement copy is missing"; exit 1; }
  lune run tests/run -- tests/acceptance/c0005/worktree.spec.luau'

finish
