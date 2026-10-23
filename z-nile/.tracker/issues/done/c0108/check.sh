#!/usr/bin/env bash
# Acceptance checks for c0108. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the repo root
# sequestered specs: here before `./zn done`, promoted to tests/acceptance/c0108 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0108"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
quoted() {
	if grep -R -n -F '.cache/board-ci' tests --include='*.spec.luau'; then
		echo "a spec already in tests/ still names the download directory as a fixture"
		return 1
	fi
	lune run tests/run -- tests/acceptance/c0048/board-docs.spec.luau tests/acceptance/c0049/spec-isolation.spec.luau
}
check "AC1: no spec in tests/ names .cache/board-ci, and the board docs and isolation specs pass" quoted

finish
