#!/usr/bin/env bash
# Acceptance checks for f0425. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0425 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0425"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# AC1's spec is f0437's, in the gate (z-nile/tests/tooling) and on main.
check "AC1: the app is still copied from this mockup (the page is the mockup plus its two edits)" lune run tests/run -- tests/tooling/app-copy.spec.luau
# AC2-AC6: the sequestered mockup spec, one case per criterion (each case is named by its AC). Each line runs the whole
# spec, a file read, so a failing case fails all five lines and the case name in the output says which criterion broke.
check "AC2: every kind of item has its own route and a Talk control, and the four other views are routed" lune run tests/run -- "$A/mockup.spec.luau"
check "AC3: the mockup's script calls no network API, and its only URLs are Google Fonts'" lune run tests/run -- "$A/mockup.spec.luau"
check "AC4: the mockup opens light in the gold-e colours and fonts, with no purple status or series colour" lune run tests/run -- "$A/mockup.spec.luau"
check "AC5: README.html uses the same fonts, opens light whatever the OS prefers, and has the theme button" lune run tests/run -- "$A/mockup.spec.luau"
check "AC6: the mockup names the seven stages and says what a raft is" lune run tests/run -- "$A/mockup.spec.luau"

finish
