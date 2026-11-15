#!/usr/bin/env bash
# Acceptance checks for c0258. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0258 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0258"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: ./zn -h, ./zn --help and -h/--help after any command print usage and run nothing; a value another option takes is not help; every command has an entry" lune run tests/run -- "$A/usage.spec.luau" "$A/help.spec.luau"
check "AC2: after a lost race land pushes again with no gate when main moved by tracker state alone and changed no capture file, and runs the gate again on the merged tree otherwise, saying already landed when main took the change, folding the gate's row on every try" lune run tests/run -- "$A/landrace.spec.luau" "$A/race.spec.luau"
check "AC3: one land makes up to ten pushes with one gate run, an unmoved failed push is a push failure, a broker with no answer stops at once, and the last lost race gives up naming the last push" lune run tests/run -- "$A/landrace.spec.luau" "$A/retries.spec.luau"
check "AC4: a push that reports a failure while origin/main holds its commit has landed, and a branch whose own changes main already holds says already landed and exits 0, also after merging that main" lune run tests/run -- "$A/landrace.spec.luau" "$A/landed.spec.luau"
check "AC5: zz-rules' Landing step states the regate rule, the ten pushes, the landed and already-landed outcomes and -h, and no longer says a lost push never reruns the gate; the capture lesson counts already landed as landed" lune run tests/run -- "$A/docs.spec.luau"

finish
