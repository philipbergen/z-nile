#!/usr/bin/env bash
# Acceptance checks for c0120. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home: the root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0120 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0120"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: z-nile/projects.toml gives each project a home; pickman's is pickman/, tracker/ is retired" lune run tests/run -- "$A/registry-home.spec.luau"
check "AC2: pickman's files and tracker items live in pickman/, and nothing of them is left at the old places" lune run tests/run -- "$A/layout.spec.luau"
check "AC3: a check.sh runs from its project's home; find and members print paths from the caller's folder" lune run tests/run -- "$A/homes.spec.luau"
check "AC4: the runner runs from a project's home, with that home's specs, aliases and .cache" lune run tests/run -- "$A/runner-home.spec.luau"
check "AC5: the require graph resolves per folder like Lune, and the selector picks per project" lune run tests/run -- "$A/graph-homes.spec.luau"
check "AC6: each project has its own gate, its stages read from its home, and --plan runs nothing" lune run tests/run -- "$A/gate-homes.spec.luau"
check "AC7: done and promote-check promote a pickman member's specs into pickman/tests/acceptance, checked from there" lune run tests/run -- "$A/promote-home.spec.luau"
check "AC8: capture and history follow an item across the move into pickman/.tracker" lune run tests/run -- "$A/trail-home.spec.luau"
check "AC9: ./zn busy lists active rafts, branches and worktrees that hold the given paths" lune run tests/run -- "$A/freeze.spec.luau"
check "AC10: the old places stay empty: audit and the gate fail on a retired-root file or a misplaced spec folder" lune run tests/run -- "$A/old-roots.spec.luau"
check "AC11: every path an unfinished item's check.sh names exists from its project's home" lune run tests/run -- "$A/check-paths.spec.luau"
check "AC12: CI skips project-root pushes, runs dispatched specs from their home, and the beta job runs from pickman/" lune run tests/run -- "$A/ci.spec.luau"
check "AC13: the skills, AGENTS.md, SETUP.md, the templates and the usage say where pickman lives" lune run tests/run -- "$A/docs.spec.luau"
check "AC14: the guard and structure specs pass in both homes" \
  bash -c 'lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/meta/architecture.spec.luau tests/acceptance/c0049/spec-isolation.spec.luau && cd pickman && lune run tests/run -- tests/meta/architecture.spec.luau tests/meta/fence.spec.luau'
check "AC15: the real tracker audits clean" ./zn audit
# AC16 reads origin as of the last fetch: run `./zn sync --fetch` first (Implementation step 11; a fetch from a
# check.sh with nothing new is refused by the ref guard)
check "AC16: as of the last fetch, nothing but this raft holds tracker/, src/ or tests/: no other raft active, no branch or worktree changing them" \
  ./zn busy tracker src tests
check "AC17: R0012, whose RC1 can't resolve after the move, is done (Guess 4 (a))" \
  bash -c 'case "$(./zn find R0012)" in */rafts/done/R0012) exit 0 ;; *) echo "R0012 is at $(./zn find R0012), not done"; exit 1 ;; esac'

finish
