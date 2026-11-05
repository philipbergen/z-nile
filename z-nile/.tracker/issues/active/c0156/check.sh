#!/usr/bin/env bash
# Acceptance checks for c0156. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0156 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0156"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the shared pin rule keeps every line break, tolerates only item ids, line endings, spaces within a line, a line's trailing whitespace, a comma before a brace and the text's outer blank lines, keeps \v and \f as they are, and its join and delete helpers read through the same normaliser and refuse a miss" \
	lune run tests/run -- "$A/pin.spec.luau"
check "AC2: both whole-file pins take the rule from the shared module, carry no copy of it, and hold the digests prep computed for pinned files that still hash to them" \
	lune run "$A/consumers.luau" -- "$ZN_ROOT"
# the pins are pickman's specs and read pickman's files from its home (the pattern c0172's AC4 uses)
check "AC3: c0103's narrowed.spec and c0128's golden.spec pass on the pinned files as they are, their in-memory mutant cases (a comment join, a deleted assertion) and line-ending cases included (a regression check: green before and after)" \
	bash -c 'cd "$ZN_ROOT/pickman" && lune run tests/run -- ../pickman/tests/acceptance/c0103/narrowed.spec.luau ../pickman/tests/acceptance/c0128/golden.spec.luau'
check "AC4: the testing skill and the narrowing lesson name the shared rule" \
	lune run tests/run -- "$A/docs.spec.luau"
check "AC5: R0045's mutation record lists a join entry in each pinned file that turns one line break after a comment into a space and changes the pin, and refuses a folder that is not the pickman home of a separate clone, each of its four conditions on its own" \
	lune run "$A/record.luau" -- "$ZN_ROOT"
check "AC6: c0103's and c0128's own acceptance checks still pass" \
	bash -c 'bash "$("$ZN_ROOT/zn" find c0103)/check.sh" && bash "$("$ZN_ROOT/zn" find c0128)/check.sh"'
check "AC7: each pin's own verdict rejects every derived mutant of each file it pins (assertions deleted or commented out, comment lines joined, one same-length edit of every line; by an assertion of the pin, not a helper's raise), and accepts the file as it is and in CRLF, the pins running in a closed environment" \
	lune run "$A/kills.luau" -- "$ZN_ROOT"

finish
