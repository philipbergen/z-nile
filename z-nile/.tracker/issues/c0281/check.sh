#!/usr/bin/env bash
# Acceptance checks for c0281. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0281 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0281"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# The mutation run (AC2, AC3) is check.sh's alone: mutants.luau copies the engine into one folder under this home's
# .cache and runs the spec once per mutant, so it runs at done and never in the gate (it is no .spec file).

check "AC1: tests/tooling/board-review.spec passes, every case of it" \
	lune run tests/run -- tests/tooling/board-review.spec.luau
check "AC2: every mutant that keeps the round-file rule from boardview.rounds (a filter before it in eight spellings and places, a folder left out by its kind or its state, the keeper chain cut, an own count, a captured call) turns board-review.spec red on an assertion, and the spec puts boardview.rounds back" \
	lune run "$A/mutants.luau" -- mutants
check "AC3: an edit of board.luau that keeps the behaviour, whether it adds what the old source pin forbade, respells what it required or hands the rule a path twice, leaves board-review.spec green" \
	lune run "$A/mutants.luau" -- equivalents

ac4() {
	local f=skills/zz-arch/lessons/one-reader-per-format.md
	grep -qF -- 'pin it with a spy on the shared function that sees every input (c0281)' "$f" &&
		! grep -qF -- "pin the caller's source for the pattern" "$f"
}
check "AC4: the zz-arch lesson that restated the source pin names the spy instead" ac4

# Overrides: none. The specs that read the same rounds pass (the board's model and page, c0118's model, metrics and view).
check "AC5: the board's other specs and c0118's round specs still pass" \
	lune run tests/run -- tests/tooling/board.spec.luau tests/acceptance/c0118/model.spec.luau \
		tests/acceptance/c0118/metrics.spec.luau tests/acceptance/c0118/view.spec.luau

finish
