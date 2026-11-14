#!/usr/bin/env bash
# Acceptance checks for c0262. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0262 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0262"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# check "ACn: <statement>" lune run tests/run -- "$A/<name>.spec.luau"
check "AC1: the view holds only the fixed files, the ask and the approved design as given (the layer's edits apart), and a diff with no bookkeeping" lune run tests/run -- "$A/view.spec.luau"
check "AC2: the view's id follows the design, the contract and the patch id, not the README or the diff text" lune run tests/run -- "$A/view.spec.luau"
check "AC3: the reviewer's README sets the one question, the two gaps and the two verdicts" lune run tests/run -- "$A/view.spec.luau"
check "AC4: an unreadable review is not read" lune run tests/run -- "$A/verdict.spec.luau"
check "AC5: the ticket's state follows its reviews, a second off-course blocks" lune run tests/run -- "$A/verdict.spec.luau"
check "AC6: a finished layer keeps the next layer from starting until its final review is on course" lune run tests/run -- "$A/work.spec.luau"
check "AC7: off course rebuilds the layer or goes back to z-design by the gap" lune run tests/run -- "$A/work.spec.luau"
check "AC8: a second off-course verdict or an unreadable review blocks for the human" lune run tests/run -- "$A/work.spec.luau"
check "AC9: a layer read without the fact is not held up" lune run tests/run -- "$A/work.spec.luau"
check "AC10: on a real layer the view holds no trail, the state follows the committed reviews, done refuses an off-course ticket" lune run tests/run -- "$A/fixture.spec.luau"
check "AC11: the dispatcher runs the review in the view folder, lands it in the ticket's folder, and runs again only after a change" lune run tests/run -- "$A/dispatch.spec.luau"
check "AC12: zz-review, zz-execute, zz-rules and z-design say the ticket's final review" lune run tests/run -- "$A/docs.spec.luau"
check "AC13: a layer is complete only when its ticket's final review is on course (c0248's completion.layer, extended; red until c0248 is done)" lune run tests/run -- "$A/complete.spec.luau"

finish
