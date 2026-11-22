#!/usr/bin/env bash
# Acceptance checks for d0434. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0434 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0434"

# The cases of one spec file run in order and share its fixture, so each line runs the whole file; the file's
# case name for the criterion is the one that fails.
check "AC1: a conflicted layer leaves the rebase in progress, exit 3, names layer, files and commands, pushes and emits nothing" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC2: a restack while one is in progress refuses and names both commands" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC3: work next names the resolve-and-continue action while a restack is stopped" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC4: --continue refuses unmerged paths and staged conflict markers, naming them" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC5: --continue finishes, restacks the layers above equal to a by-hand rebase and emits restacked once" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC6: --abort restores every branch, origin and the worktree" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC7: a hand-rebased local layer is never reset from origin" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC8: a restack that died after a hand-continued rebase is finished by a plain restack" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC9: a foreign commit on origin's layer stops the restack with nothing changed" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC10: a red check.sh pushes nothing for its layer or later" lune run tests/run -- "$A/restack-conflict.spec.luau"
check "AC11: zz-execute and z-work tell the worker to resolve, continue, and when to ask" lune run tests/run -- "$A/restack-conflict.spec.luau"

finish
