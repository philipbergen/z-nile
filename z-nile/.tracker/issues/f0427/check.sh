#!/usr/bin/env bash
# Acceptance checks for f0427. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0427 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0427"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "AC1: <statement>" lune run tests/run -- "$A/<name>.spec.luau"
# Each spec builds zn once into .cache/zn-test (acceptance/lib/zn.luau) and works only in fixtures under .cache.
check "AC1: zn runs with no Lune on PATH; the linux build carries the pinned Linux Lune" lune run tests/run -- "$A/embed.spec.luau"
check "AC2: the linux build is proven on Linux (waits on the owner: a second CI workflow contradicts c0172, the only workflow is deploy.yml)" bash -c 'echo "AC2 waits on the owner'"'"'s ruling: prove Linux by a CI workflow (overriding c0172) or by a run on the owner'"'"'s Omarchy machine"; exit 1'
check "AC3: the cache is verified each run, 0700, and refuses symlinks and a relative XDG_CACHE_HOME" lune run tests/run -- "$A/cache.spec.luau"
check "AC4: init hides .tracker and .worktree once, changes no tracked file or ref, refuses pickman" lune run tests/run -- "$A/init.spec.luau"
check "AC5: tracker commands write only under .tracker and the data-dir origin" lune run tests/run -- "$A/tracker-writes.spec.luau"
check "AC6: approve refuses without a terminal and under ZN_DISPATCH or ZN_APPROVE_SESSION; CPU limit only lowered" lune run tests/run -- "$A/frontdoor.spec.luau"
check "AC7: every manifest skill is under .tracker/skills and printed by work; nothing written under .claude; stale edition fails" lune run tests/run -- "$A/skills.spec.luau"
check "AC8: doctor and work name each missing program" lune run tests/run -- "$A/doctor.spec.luau"
check "AC9: zn run keeps the bounded runner's guarantees" lune run tests/run -- "$A/run.spec.luau"
check "AC10: zn gate refuses an empty command, bounds it, catches a moved ref, asks before a new command" lune run tests/run -- "$A/gate.spec.luau"
check "AC11: sequestered files come from the ready commit and cannot be merged" lune run tests/run -- "$A/sequester.spec.luau"
check "AC12: zn pr upstream and zn land stop on every done --check refusal" lune run tests/run -- "$A/donecheck.spec.luau"
check "AC13: host commits carry no .tracker, .worktree, .cache or .claude path" lune run tests/run -- "$A/commit.spec.luau"
check "AC14: squash merge lands, close frees the claim, a later commit reopens review" lune run tests/run -- "$A/prstate.spec.luau"
check "AC15: the board shows the raft in each stage in turn" lune run tests/run -- "$A/board.spec.luau"

finish
