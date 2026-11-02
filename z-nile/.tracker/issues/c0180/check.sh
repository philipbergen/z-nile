#!/usr/bin/env bash
# Acceptance checks for c0180. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0180 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0180"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the engine is split by command, with a thin dispatch core that narrows" lune run tests/run -- "$A/split.spec.luau"
check "AC2: the engine traces the command it runs, by physical .cache/spec-trace paths only" lune run tests/run -- "$A/trace.spec.luau"
check "AC3: the runner records each passing spec's commands through recordkey, merging by union" lune run tests/run -- "$A/record.spec.luau" "$A/realtree.spec.luau"
check "AC4: commandrecord keys, parses, renders and merges the record" lune run tests/run -- "$A/commandrecord.spec.luau"
check "AC5: with records, an engine file is an input by requires, declarations, missing records or commands" lune run tests/run -- "$A/select.spec.luau"
check "AC6: affected --recorded selects by commands across worktrees, failing closed" lune run tests/run -- "$A/endtoend.spec.luau"
check "AC7: zz-test, zz-arch and zz-rules state the new rules" lune run tests/run -- "$A/docs.spec.luau"
check "AC8: every engine-text reader declares its engine input" lune run tests/run -- "$A/inputs.spec.luau"
check "AC9: the three overridden specs hold exactly their narrowings" lune run tests/run -- "$A/narrowed.spec.luau"
check "AC10: the gate's selection passes --recorded; fingerprints never load records" lune run tests/run -- "$A/gate.spec.luau"

finish
