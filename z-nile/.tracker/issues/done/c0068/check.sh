#!/usr/bin/env bash
# Acceptance checks for c0068. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0068 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0068"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# stop.spec is one end-to-end fixture: it runs once, and each check requires its own named cases to exist and pass.
spec="$A/stop.spec.luau"
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

check "AC1: stop refuses outside the main checkout, for a raft that is not readied, and with a member in done/" cases_pass \
  "stop refuses outside the main checkout" "stop refuses a raft with a member already in done/"
check "AC2: stop moves the raft back in one commit, stamped prepared; a round trip is byte-exact" cases_pass \
  "stop moves a readied raft back" "a ready and stop round trip restores"
check "AC3: prompt.md and the active directory are removed; the main checkout is clean and current" cases_pass \
  "stop removes prompt.md"
check "AC4: a started raft's branch is left and named; the raft can be readied again" cases_pass \
  "stop of a started raft" "a stopped raft can be readied again"
check "AC5: status refuses any move of a readied item and names stop" cases_pass "status refuses to move a readied item"
check "AC6: stop gives back a legacy-started raft without moving it" cases_pass "stop gives back a raft claimed by the legacy start"
check "AC7: the stop-raft skill, the tracker skill and AGENTS.md" bash -c '
  s=../.claude/skills/stop-raft/SKILL.md
  [ -f "$s" ] || { echo "no $s"; exit 1; }
  grep -q "^name: stop-raft$" "$s" || { echo "stop-raft: name"; exit 1; }
  grep -qF "./zn stop" "$s" || { echo "stop-raft: ./zn stop"; exit 1; }
  grep -qi "main checkout" "$s" || { echo "stop-raft: main checkout"; exit 1; }
  grep -qiE "(branch|pull request|PR).*(left|leave)|(left|leave).*(branch|pull request|PR)" "$s" || { echo "stop-raft: branch and PR are left"; exit 1; }
  grep -qF "stop-raft/SKILL.md" ../AGENTS.md || { echo "AGENTS.md: stop-raft row"; exit 1; }
  grep -qF "./zn stop" ../.claude/skills/tracker/SKILL.md || grep -qE "^\| stop \|" ../.claude/skills/tracker/SKILL.md || { echo "tracker skill: stop"; exit 1; }'

finish
