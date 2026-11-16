#!/usr/bin/env bash
# Acceptance checks for c0392. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0392 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0392"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: c0210's promoted folder and finished check.sh are exactly its reviewed files with lobby-start.spec and the AC11 check removed, nothing added (watch files aside), and nothing outside the trackers, and no check.sh, names the removed file" \
	python3 -I "$A/narrow.py" "$ZN_ROOT"
check "AC2: c0210's acceptance checks pass from its finished folder, without lobby-start.spec" \
	bash -c 'bash "$("$ZN_ROOT/zn" find c0210)/check.sh"'

finish
