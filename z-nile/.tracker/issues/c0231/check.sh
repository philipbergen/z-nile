#!/usr/bin/env bash
# Acceptance checks for c0231. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0231 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0231"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a yes whose output no head reads straight from its pipe is refused as a follow, however it is reached, ended, nested or redirected" lune run tests/run -- "$A/refused.spec.luau"
check "AC2: yes piped straight into a head with a non-negative count, or into a command bounded by its own means (the wrapper, ./zn, a check.sh), passes in every spelling and nesting, and the wrapper runs any yes" lune run tests/run -- "$A/allowed.spec.luau"
check "AC3: a pipe into anything but such a head (a filter, a loop, xargs, a later head, a negative count) does not save yes" lune run tests/run -- "$A/consumers.spec.luau"
check "AC4: a yes that is no command (a mention, an argument, a case pattern) passes, and a closed case hides nothing" lune run tests/run -- "$A/mentions.spec.luau"
check "AC5: a Monitor command may run yes, and a background call judges yes as before" lune run tests/run -- "$A/contexts.spec.luau"
check "AC6: the refusal names the follow rule, the head that ends yes and the wrapper, and the hook entry refuses with exit 2" lune run tests/run -- "$A/refusal.spec.luau"
check "AC7: zz-test restates the rule: a yes no head reads is a follow, and yes is no longer listed as passing" lune run tests/run -- "$A/docs.spec.luau"
check "AC8: the promoted seatbelt specs stay green: c0191 boundcmd, hooks and docs, c0244 homes, the review fixes" lune run tests/run -- tests/acceptance/c0191/boundcmd.spec.luau tests/acceptance/c0191/hooks.spec.luau tests/acceptance/c0191/docs.spec.luau tests/acceptance/c0244/homes.spec.luau tests/tooling/bounded-review.spec.luau

finish
