#!/usr/bin/env bash
# Acceptance checks for c0460. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0460 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0460"

check "AC1: finish refuses a built layer with the Mutants line unless mutants.md holds only killed rows, and its exemptions hold" lune run tests/run -- "$A/finish-mutants.spec.luau"
check "AC2: the template, z-design, zz-execute and zz-review say the new rules" lune run tests/run -- "$A/skills-text.spec.luau"
check "AC3: no acceptance spec of this ticket, or of a ticket carrying the line, requires an alias other than @tests/lib/* or @lune/*" lune run tests/run -- "$A/requires.spec.luau"

finish
