#!/usr/bin/env bash
# Acceptance checks for c0166. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0166 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0166"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a lesson is selected by core, paths:, tag area or skill folder, and nil paths does not filter" \
	lune run tests/run -- "$A/relevance.spec.luau"
check "AC2: --for reads Touched modules, --diff unions the committed diff, and another project is left out" \
	lune run tests/run -- "$A/for-paths.spec.luau"
check "AC3: paths: parse, unlisted tags, a concrete check, and today's area rows" \
	bash -c 'lune run tests/run -- "$1" && lune run tests/run -- "$2"' _ "$A/parse-check.spec.luau" "$A/named-areas.luau"
check "AC4: a later source with an unchanged check line is refused, and metrics lists recurrence" \
	lune run tests/run -- "$A/rewrite.spec.luau"
check "AC5: five rounds need a prompt-failure note, and stream review files do not count" \
	lune run tests/run -- "$A/rounds.spec.luau"
check "AC6: the review briefs name the filtered lessons command and the five-round note" \
	lune run tests/run -- "$A/briefs.spec.luau"
check "AC7: the ready prompt filters on Touched modules and keeps every build lesson when there are none" \
	lune run tests/run -- "$A/prompt.spec.luau"

finish
