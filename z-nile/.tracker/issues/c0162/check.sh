#!/usr/bin/env bash
# Acceptance checks for c0162. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0162 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0162"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the runner's pin reader: rokit.toml's [tools] lune pin, refusing an ambiguous file; the running version; where rokit.toml is looked for; a check that passes only the pin, with the fix" lune run tests/run -- "$A/pin.spec.luau"
check "AC2: the runner runs on the pinned Lune: the outermost run names the version first, tries rokit's Lune when the shell's is another, and refuses otherwise before any spec; every inner run checks itself; an ambiguous rokit.toml refuses" lune run tests/run -- "$A/runner.spec.luau"
check "AC3: zz-test, pickman-test and SETUP.md say the runner runs on rokit.toml's Lune, with the fix" lune run tests/run -- "$A/docs.spec.luau"
check "AC4: the tooling's structural rules hold" lune run tests/run -- tests/meta/architecture.spec.luau

finish
