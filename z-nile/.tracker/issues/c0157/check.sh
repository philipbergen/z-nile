#!/usr/bin/env bash
# Acceptance checks for c0157. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0157 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0157"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# only "$A/…" spec paths here: main's check-paths scan reads a literal path from z-nile/ before this item lands
G="$A/gate-slots.spec.luau"
W="$A/tripwire.spec.luau"
check "AC1: concurrent gates on one machine share max(1, floor(cpus / 8)) gate slots: a lone gate takes one at once, a gate beyond them waits until one is given back, a stale slot is free, and a gate inside a guarded test run takes none" lune run tests/run -- "$G"
check "AC2: z-nile/check.sh runs each project's spec stage inside a gate slot, and the Stop hook's wait for one is bounded" lune run tests/run -- "$G"
check "AC3: the tripwire's fixture-ref message names each appeared ref's author, date and subject, and that another session's prototype under a fixture identity causes it too" lune run tests/run -- "$W"
check "AC4: z-design, zz-execute and zz-test say, in the same words, that prototypes live in scratch clones and nothing is committed in the real repository under a fixture identity" lune run tests/run -- "$W"

finish
