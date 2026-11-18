#!/usr/bin/env bash
# Acceptance checks for d0413. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0413 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0413"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# One run of the fast acceptance spec; each criterion reads its own cases from the output.
export OUT; OUT="$(lune run tests/run -- "$A/loops.spec.luau" 2>&1)"
# passes "<case name>": the file loaded, ran, and did not fail that case
passes() {
	# the file holds five cases: a run that counted another number proves nothing about a case it does not name
	[[ "$(sed -nE "s/^([0-9]+) passed, ([0-9]+) failed, 1 spec files\$/\1+\2/p" <<<"$OUT" | bc)" == 5 ]] || return 1
	! grep -q "could not load spec" <<<"$OUT" || return 1
	! grep -qF ":: $1" <<<"$OUT"
}

# check.sh only (not promoted): the reviewed list is the file it was on main, so neither loop was listed instead of
# rewritten. A later issue may change the list; this line is judged against this branch's merge base alone.
check "AC1: the scan finds no problem in either file, and the reviewed list is unchanged" bash -c '
	[[ "$(sed -nE "s/^([0-9]+) passed, ([0-9]+) failed, 1 spec files\$/\1+\2/p" <<<"$OUT" | bc)" == 5 ]] &&
	! grep -qF ":: the loop scan finds no problem in guesses.luau or raftplan.luau" <<<"$OUT" &&
	git diff --quiet "$(git merge-base HEAD origin/main)" -- tests/lib/loops.luau'
check "AC2: guesses.parse still ignores trailing empty lines" \
	passes "guesses.parse ignores trailing empty lines, however many and however they end"
check "AC3: the planner keeps its dependency order and its ring fallback" bash -c '
	passes() { [[ "$(sed -nE "s/^([0-9]+) passed, ([0-9]+) failed, 1 spec files\$/\1+\2/p" <<<"$OUT" | bc)" == 5 ]] && ! grep -qF ":: $1" <<<"$OUT"; }
	passes "the planner keeps its dependency order, lowest id first among the free" &&
	passes "a ring takes the lowest id left, then goes on in dependency order"'
check "AC4: a list that repeats an id is planned, every entry once" \
	passes "a list that repeats an id is planned, every entry once, instead of never returning"
check "AC5: the two loop-scan specs pass" \
	lune run tests/run -- tests/meta/scanning-loops.spec.luau tests/acceptance/c0193/tree.spec.luau

finish
