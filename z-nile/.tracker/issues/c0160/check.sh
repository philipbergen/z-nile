#!/usr/bin/env bash
# Acceptance checks for c0160. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0160 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0160"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# c0141's AC3 note: no literal path to c0120's promoted folder here (main's scan reads them before c0141 lands)
S="$A/third-project.spec.luau"
C120="$PWD/tests/acceptance/c0120"
check "AC1: the check-paths scan reads a third registered project's check.sh files, backlog and active, from its home, checks the paths they name, and exempts its own Touched work, as it does for pickman and z-nile" lune run tests/run -- "$S"
check "AC2: a word starting with any registered project's home is a literal path to the check-paths reader, the homes taken from the scanned checkout's registry (or, called alone, the running checkout's), never a hand list" lune run tests/run -- "$S"
check "AC3: c0120's finished-file reader takes the homes the same way" lune run tests/run -- "$S"
check "AC4: c0120's check-paths and finished specs, and c0141's specs, still pass" lune run tests/run -- "$C120/check-paths.spec.luau" "$C120/finished.spec.luau" "$PWD"/tests/acceptance/c0141/*.spec.luau

finish
