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
# The suite's half (bounded.spec) uses a stand-in clock and CPU meter and burns nothing. The real-limit proof spins CPU and
# waits for real limits (about four seconds of CPU, fifteen of wall clock): it is a script here, never a spec, and it runs
# only while the sequestered folder exists (before `./zn done`: afterwards the promoted file is inert and nothing runs
# it). It is bounded independently of the runner it tests: a kernel CPU cap (`ulimit -t 60`, a shell builtin) in front of
# it, and a CPU bound inside each spinner.
check "AC1: ./zn run keeps status and output, hands out its limits, refuses what it cannot honour and classifies a wall-clock stop, a CPU stop and a near miss (stand-ins); and, before ./zn done only, against real processes, stops a spinner at --cpu and --time with its whole tree, what a command leaves, the group of a killed runner and of a gone parent, and passes the signals" \
	bash -c "lune run tests/run -- '$A/bounded.spec.luau' && { [ '$A' != '$HERE/acceptance' ] || { ulimit -t 60; '$ZN_ROOT/zn' run --time 120 -- lune run '$A/proof-bounded.luau'; }; }"
check "AC2: the PreToolUse hook (Bash and Monitor) refuses unbounded interpreters, loops, follows and background calls, names the wrapper, passes the gate's commands, fails open, and is itself bounded (its limit is asked for in the suite; a hook entry that hangs is really stopped by it in AC5's proof script, before ./zn done only)" \
	lune run tests/run -- "$A/boundcmd.spec.luau" "$A/hooks.spec.luau"
check "AC3: ./zn reap's rules stop orphans, expired ./zn run commands and an ending session's processes, and keep everything else" lune run tests/run -- "$A/reap.spec.luau"
# ps and lsof cannot start inside the spec jail, so the reaper's check against real processes runs here, bounded by the
# runner under test; its only root is a throwaway folder under .cache
check "AC4: ./zn reap stops real decoy processes under its root, reports each, and leaves the others alone" "$ZN_ROOT/zn" run --time 180 -- lune run "$A/reap-e2e.luau"
# AC5 and the real-limit half of AC2: spins CPU for about four seconds, before ./zn done only, never a spec
check "AC5: the spec runner and the engine give their processes a CPU-time limit that only ever lowers the caller's (PICKMAN_SPEC_CPU 1200 s, ZN_ENGINE_CPU 1800 s: what is asked for is observed through a stand-in ulimit), and, before ./zn done only, a CPU burner under the runner's limit, a spinning engine and a hanging hook entry are really stopped by their limits" \
	bash -c "lune run tests/run -- '$A/runner-cpu.spec.luau' '$A/engine-cpu.spec.luau' && { [ '$A' != '$HERE/acceptance' ] || { ulimit -t 60; '$ZN_ROOT/zn' run --time 120 -- lune run '$A/proof-limits.luau'; }; }"
check "AC6: the rule is worded the same everywhere, sync and the gate run the reaper, and every list names the new commands" lune run tests/run -- "$A/docs.spec.luau"

finish
