#!/usr/bin/env bash
# Acceptance checks for d0295. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0295 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0295"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

# A fixture's publishes and pushes reach a dispatched step's own broker and git wrapper until d0355/d0298 strip the
# step's variables (fence.STEP_VARS); the CLI specs run without them and without z-nile/bin on PATH, as d0298's
# fence will (d0295 E4). The step's git configuration entries stay: fence.sh replaces them for every spec (d0298's
# fence.STEP_HANDLED). Interactively there is nothing to strip.
nostep() {
  local path
  path=$(tr ':' '\n' <<<"$PATH" | grep -v '/z-nile/bin/*$' | paste -sd: -)
  env -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN -u ZN_DISPATCH -u ZN_HEADLESS -u ZN_DISPATCHER_PID \
    -u ZN_DISPATCH_DIR -u ZN_DISPATCH_HOME -u ZN_REAL_GIT -u ZN_REAL_GH -u ZN_AGENT_GH_TOKEN PATH="$path" "$@"
}

check "AC1: stack.orderSection cuts the Order at the next level-two heading, so Cross-raft waits are never layers" \
  lune run tests/run -- "$A/order-section.spec.luau"
check "AC2: readycheck.reason (ready and work) refuses an Order start would refuse and accepts Cross-raft waits" \
  lune run tests/run -- "$A/order-ready.spec.luau"
check "AC3: the carried status <R> prepared refuses an Order start would refuse, publishes nothing, takes Cross-raft waits" \
  nostep lune run tests/run -- "$A/order-cli.spec.luau"
check "AC4: z-raft, its lessons, the raft template and the prompt template name Cross-raft waits" \
  lune run tests/run -- "$A/order-docs.spec.luau"
check "AC5: every prepared backlog raft's Order text is accepted, except those listed exempt, re-raft or cycle" \
  bash -c 'cd "$ZN_ROOT" && lune run "$1"' _ "$HERE/experiments/order-scan.luau"
check "AC6: the existing stack, readycheck, work, ready, prompt and rafting specs pass" \
  nostep lune run tests/run -- tests/tooling/stack.spec.luau tests/tooling/readycheck.spec.luau \
  tests/tooling/work.spec.luau tests/tooling/stack-land.spec.luau tests/tooling/stack-fix.spec.luau \
  tests/acceptance/c0116/recombine.spec.luau tests/acceptance/c0116/plan-cli.spec.luau tests/acceptance/c0115/prompt.spec.luau tests/acceptance/c0067/ready.spec.luau

finish
