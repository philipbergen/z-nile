#!/usr/bin/env bash
# Acceptance checks for c0120. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home: z-nile/
# sequestered specs: here before `./zn done`, promoted to z-nile/tests/acceptance/c0120 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0120"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: z-nile/projects.toml's roots give each project its home, pickman/ and z-nile/; tracker/ is retired" lune run tests/run -- "$A/registry-home.spec.luau"
check "AC2: pickman's files live in pickman/, the tooling's tests in z-nile/tests/, and nothing is left at the old places" lune run tests/run -- "$A/layout.spec.luau"
check "AC3: a check.sh runs from its project's home; find and members print paths from the caller's folder" lune run tests/run -- "$A/homes.spec.luau"
check "AC4: the runner runs from a project's home, with that home's specs, aliases and .cache, and refuses elsewhere" lune run tests/run -- "$A/runner-home.spec.luau"
check "AC5: the require graph resolves per folder like Lune, and the selector picks per project" lune run tests/run -- "$A/graph-homes.spec.luau"
check "AC6: each project has its own gate, its stages read from its home, and --plan runs nothing" lune run tests/run -- "$A/gate-homes.spec.luau"
check "AC7: done and promote-check promote a member's specs into its home's tests/acceptance, checked from there" lune run tests/run -- "$A/promote-home.spec.luau"
check "AC8: capture and history follow an item across the move into pickman/.tracker" lune run tests/run -- "$A/trail-home.spec.luau"
check "AC9: ./zn busy lists active rafts, branches and worktrees that hold the given paths" lune run tests/run -- "$A/freeze.spec.luau"
check "AC10: the old places stay empty: audit and the gate fail on a retired-root file, a root tests/ or a misplaced spec folder" lune run tests/run -- "$A/old-roots.spec.luau"
check "AC11: every path an unfinished item's check.sh names exists from its home, and a finished one's still resolves" lune run tests/run -- "$A/check-paths.spec.luau" "$A/finished.spec.luau"
check "AC12: CI runs one gate job per project, skips project-root pushes, runs dispatched specs from their home, and the beta job from pickman/" lune run tests/run -- "$A/ci.spec.luau"
check "AC13: the skills, AGENTS.md, SETUP.md, the templates and the usage say where each project lives" lune run tests/run -- "$A/docs.spec.luau"
check "AC14: the guard and structure specs pass in both homes" \
  bash -c 'lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/meta/architecture.spec.luau tests/acceptance/c0049/spec-isolation.spec.luau && cd ../pickman && lune run tests/run -- tests/meta/architecture.spec.luau tests/meta/fence.spec.luau'
check "AC15: the real tracker audits clean" "$ZN_ROOT/zn" audit
# AC16 reads origin as of the last fetch: run `./zn sync --fetch` first (Implementation step 11; a fetch from a
# check.sh with nothing new is refused by the ref guard)
check "AC16: as of the last fetch, nothing but this raft holds tracker/, src/ or tests/: no other raft active, no branch or worktree changing them" \
  "$ZN_ROOT/zn" busy tracker src tests
check "AC17: R0012, whose RC1 can't resolve after the move, is done (decided: Guess 4 (a))" \
  bash -c 'at=$("$ZN_ROOT/zn" find R0012); case "$at" in */rafts/done/R0012) exit 0 ;; *) echo "R0012 is at $at, not done"; exit 1 ;; esac'
check "AC18: every item's check.sh and acceptance file is its text before the move: unchanged, or a finished check.sh with exactly the rewrite" \
  lune run "$A/finished.luau" -- "$ZN_ROOT"

finish
