#!/usr/bin/env bash
# Acceptance checks for c0131. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0131 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0131"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: outside spec runs the ref guard accepts an empty transaction and a remote-tracking fetch" lune run tests/run -- "$A/accept.spec.luau"
check "AC2: it still refuses an empty transaction in a spec run, branch updates, deleted refs and any update in a spec run" lune run tests/run -- "$A/refuse.spec.luau"

finish
