#!/usr/bin/env bash
# Acceptance checks for c0191. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0191 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0191"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: ./zn run stops a command at its wall-clock and CPU limits, with its whole tree, when it ends, and when the runner dies" lune run tests/run -- "$A/bounded.spec.luau"
check "AC2: the PreToolUse hook (Bash and Monitor) refuses unbounded interpreters, loops, follows and background calls, names the wrapper, passes the gate's commands, fails open, and is itself bounded" lune run tests/run -- "$A/boundcmd.spec.luau" "$A/hooks.spec.luau"
check "AC3: ./zn reap's rules stop orphans, expired ./zn run commands and an ending session's processes, and keep everything else" lune run tests/run -- "$A/reap.spec.luau"
# ps and lsof cannot start inside the spec jail, so the reaper's check against real processes runs here, bounded by the
# runner under test; its only root is a throwaway folder under .cache
check "AC4: ./zn reap stops real decoy processes under its root, reports each, and leaves the others alone" "$ZN_ROOT/zn" run --time 180 -- lune run "$A/reap-e2e.luau"
check "AC5: the spec runner and the engine give their processes a CPU-time limit that only ever lowers the caller's (PICKMAN_SPEC_CPU 1200 s, ZN_ENGINE_CPU 1800 s)" lune run tests/run -- "$A/runner-cpu.spec.luau" "$A/engine-cpu.spec.luau"
check "AC6: the rule is worded the same everywhere, sync and the gate run the reaper, and every list names the new commands" lune run tests/run -- "$A/docs.spec.luau"

finish
