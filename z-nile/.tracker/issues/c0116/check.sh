#!/usr/bin/env bash
# Acceptance checks for c0116. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home: the root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0116 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0116"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: rafting prepared issues claims the raft only; raft: is the lock; fold, the carried move and release hold it" \
  lune run tests/run -- "$A/claims.spec.luau"
check "AC2: recombine moves all or named members between backlog rafts under one stamp and retires only an emptied raft" \
  lune run tests/run -- "$A/recombine.spec.luau" "$A/retired.spec.luau"
check "AC3: z-raft's no-argument plan keeps types, projects, the cap, solo issues and shared surfaces, in any order" \
  lune run tests/run -- "$A/plan.spec.luau"
check "AC4: raft-plan prints the plan as commands from the documents, and --apply runs them in a worktree only" \
  lune run tests/run -- "$A/plan-cli.spec.luau"
check "AC5: z-design works on one raftless issue; design reviews live on the issue and metrics rolls them up to the raft" \
  lune run tests/run -- "$A/issue-design.spec.luau"
check "AC6: the skills, the README, AGENTS.md and the usage split rafting out of design" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC7: promote-check takes an issue and copies its own acceptance specs (in a clone under .cache)" \
  lune run tests/run -- "$A/promote.spec.luau"
check "AC8: the real tree's skill links, lessons and audit stay clean with z-raft added" \
  bash -c './zn skills --check && ./zn lessons --check && ./zn audit'
check "AC9: the promoted claim, prep, start, board and remap specs, and c0115's overridden README spec, stay green" \
  lune run tests/run -- tests/acceptance/c0053/commands-prep.spec.luau tests/acceptance/c0053/commands-claim.spec.luau \
  tests/acceptance/c0053/commands-start.spec.luau tests/acceptance/c0067/*.spec.luau tests/acceptance/c0068/stop.spec.luau \
  tests/acceptance/c0070/board-refresh.spec.luau tests/acceptance/c0081/remap.spec.luau tests/acceptance/c0115/readme.spec.luau

finish
