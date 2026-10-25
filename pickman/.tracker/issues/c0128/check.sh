#!/usr/bin/env bash
# Acceptance checks for c0128. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/scripts/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `tracker.sh done`, promoted to tests/acceptance/c0128 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0128"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `tracker.sh members` and other cheap reads; everything else goes inside `check`.
check "AC1: the narrowed f0024 adapter and f0026 adapters specs pass" lune run tests/run -- tests/acceptance/f0024/adapter.spec.luau tests/acceptance/f0026/adapters.spec.luau
check "AC2: both files keep every case, in order, under its title" lune run tests/run -- "$A/titles.spec.luau"
check "AC3: each of the seven narrowed cases keeps the guard it had for the per-player boards and allows only d0124's HiscoreTop besides" lune run tests/run -- "$A/guards.spec.luau"
check "AC4: no other case changes: both files are exactly the narrowed ones" lune run tests/run -- "$A/golden.spec.luau"

finish
