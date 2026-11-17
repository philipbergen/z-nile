#!/usr/bin/env bash
# Acceptance checks for c0402. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0402 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0402"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: raftplan.CAP is 3000 and the default plan keeps the boundary: a raft's sum reaches 3,000 and not 3,001, an issue of 3,000 is not over the cap and one of 3,001 is a raft by itself" lune run tests/run -- "$A/engine.spec.luau"
check "AC2: z-raft's and z-design's skills, and the size lesson that restates the cap, say about 3,000, and none of those three says about 1,500" lune run tests/run -- "$A/skills.spec.luau"
check "AC3: the promoted c0116 plan and docs specs and f0399's plan.spec pin or fit 3,000, and pass" lune run tests/run -- "$A/pins.spec.luau" "$A/pins-f0399.spec.luau" tests/acceptance/c0116/plan.spec.luau tests/acceptance/c0116/docs.spec.luau tests/acceptance/f0399/plan.spec.luau
check "AC4: the cap changes nothing else: a solo issue stays alone and an explicit smaller cap still wins (the c0116 plan and CLI specs stay green)" lune run tests/run -- "$A/untouched.spec.luau" tests/acceptance/c0116/plan.spec.luau tests/acceptance/c0116/plan-cli.spec.luau

finish
