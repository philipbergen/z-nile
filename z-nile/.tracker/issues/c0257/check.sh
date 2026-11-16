#!/usr/bin/env bash
# Acceptance checks for c0257. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0257 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0257"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the plugin is complete, the manifest names real entry points and the settings keep the rank command empty" lune run tests/run -- "$A/app.spec.luau"
check "AC2: the model's own tests pass under node" lune run tests/run -- "$A/modeltests.spec.luau"
check "AC3: the ordering, link, additive-key and rank-command rules hold" lune run tests/run -- "$A/rules.spec.luau"
check "AC4: the place-deploy workflow ignores pushes that touch only the plugin" lune run tests/run -- "$A/deploy.spec.luau"
check "AC5: no shell string in the plugin, and the scripts stop on error" lune run tests/run -- "$A/noshell.spec.luau"
check "AC6: the documented test command runs on node 22" lune run tests/run -- "$A/docs.spec.luau"
check "AC7: fetch.sh builds the model through ./zn only and fails with its own codes" lune run tests/run -- "$A/fetch.spec.luau"
check "AC8: the board page's model is what the app reads" lune run tests/run -- "$A/contract.spec.luau"

finish
