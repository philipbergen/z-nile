#!/usr/bin/env bash
# Acceptance checks for c0286. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0286 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0286"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

# d0355 (new): under `./zn dispatch` a fixture spec inherits the dispatcher's publish broker, and every publish in a
# fixture dies in broker.request ("Operation not permitted"). The specs that publish in a fixture run without the
# dispatcher's variables until d0355 lands; the control is c0116/plan-cli on unmodified main (red with them, green
# without them, recorded in c0286's Unknowns E3).
# A spec that starts a nested dispatch must also not inherit the agent's git wrapper (`z-nile/bin` first on PATH,
# ZN_REAL_GIT): a fixture's dispatch then takes the wrapper as its real git and the wrapper calls itself without end
# (the supervisor's note of 2026-11-15 on c0286's first design session).
undispatched() {
  local path
  path=$(tr ':' '\n' <<<"$PATH" | grep -v '/z-nile/bin$' | paste -sd: -)
  env -u ZN_DISPATCH -u ZN_DISPATCH_DIR -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN -u ZN_HEADLESS -u ZN_REAL_GIT -u ZN_REAL_GH \
    PATH="$path" "$@"
}

check "AC1: raftplan.plan keeps a tie together: waits and names why, one raft whatever the cap or surface, folds into the raft that holds the rest, skips a tie one raft can't hold, and a tied raft takes nothing else" \
  lune run tests/run -- "$A/ties.spec.luau"
check "AC2: raft-plan reads tied: from the documents, --apply makes the tie one raft, and new raft with arguments takes a tied issue alone" \
  undispatched lune run tests/run -- "$A/plan-cli.spec.luau"
check "AC3: z-raft, zz-rules, z-design and raftplan's header state the tie" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC4: the families the user tied carry readable tied: lines that tie exactly each family, on every member that must carry one" \
  lune run tests/run -- "$A/family.spec.luau"
check "AC5: the real tree audits and lessons-checks clean, and the promoted raft-plan, docs and dispatch specs stay green" \
  bash -c "$(declare -f undispatched)"'; "$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && undispatched lune run tests/run -- tests/acceptance/c0116/plan.spec.luau tests/acceptance/c0116/plan-cli.spec.luau tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0117/docs.spec.luau tests/acceptance/c0117/dispatch.spec.luau tests/tooling/recombine-members.spec.luau'

finish
