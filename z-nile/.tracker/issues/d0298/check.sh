#!/usr/bin/env bash
# Acceptance checks for d0298. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0298 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0298"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

# A dispatched step's environment, as `./zn dispatch` gives it to a model step (dispatcher.luau's step env and
# credential.agentEnv): its run state, the agent's credential, and the z-nile/bin wrapper first on PATH, from the main
# checkout and from this one. The broker and the state folder are paths nothing can create, so a spec that still
# inherited them fails at once instead of waiting for an answer. The real git and gh are kept when this already runs
# inside a step (where `command -v git` is the wrapper).
dispatched() {
  local main
  main="$(cd "$(git rev-parse --path-format=absolute --git-common-dir)/.." && pwd -P)"
  env ZN_DISPATCH=1 ZN_HEADLESS=1 \
    ZN_DISPATCH_DIR=/nonexistent/d0298-ac ZN_DISPATCH_HOME=/nonexistent/d0298-ac \
    ZN_PUBLISH_BROKER=/nonexistent/d0298-ac/broker ZN_PUBLISH_TOKEN=d0298-ac ZN_DISPATCHER_PID=1 \
    ZN_REAL_GIT="${ZN_REAL_GIT:-$(command -v git)}" ZN_REAL_GH="${ZN_REAL_GH:-$(command -v gh || echo /nonexistent/gh)}" \
    GH_TOKEN=d0298-not-a-token GITHUB_TOKEN=d0298-not-a-token ZN_AGENT_GH_TOKEN=d0298-not-a-token \
    GH_CONFIG_DIR=/nonexistent/d0298-ac/gh \
    PATH="$main/z-nile/bin:$ZN_ROOT/z-nile/bin:$PATH" "$@"
}

check "AC1: an id rewrite (renumber, compact) carries every approval that held, as the same row, and no other" \
  lune run tests/run -- "$A/carry.spec.luau"
check "AC2: ready names a redesigned member's record before its approval, and still refuses a stale approval" \
  lune run tests/run -- "$A/ready-order.spec.luau"
check "AC3: a spec run started in a dispatched step's environment carries none of it" \
  dispatched lune run tests/run -- "$A/stepenv.spec.luau"
check "AC4: done-order, parallel-runner and trail-move pass in a dispatched step's environment" \
  dispatched lune run tests/run -- tests/acceptance/c0008/done-order.spec.luau \
  tests/acceptance/c0049/parallel-runner.spec.luau tests/acceptance/c0114/trail-move.spec.luau
# the slow tier holds every spec the Problem names: c0116/compact-record, c0116/claims, c0045/workstreams (c0304),
# c0114/classified and c0116/retired (c0266), c0008/done-order, c0049/parallel-runner
check "AC5: z-nile's slow tier passes" ./check.sh --slow
check "AC6: the full gate passes" ./check.sh --full

finish
