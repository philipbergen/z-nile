#!/usr/bin/env bash
# Acceptance checks for c0262. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0262 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0262"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the final review's view is the captured ask, the design without the execution's words, the check, the acceptance specs and the issue's diff, and no tracker folder" \
	lune run tests/run -- "$A/view.spec.luau"
check "AC2: ./zn done's rule: every member's newest final review must approve, a sent-back ticket blocks whatever the author answered, round 3 escalates, and a raft without a grouped record or created before the cutoff is exempt" \
	lune run tests/run -- "$A/gate.spec.luau"
check "AC3: final is a zz-review mode: a prompt that works in the view folder with no lessons line, a landing in the raft's folder, the code-review spend phase" \
	lune run tests/run -- "$A/mode.spec.luau"
check "AC4: a final review's findings are harvestable and its files are not item documents" \
	lune run tests/run -- "$A/harvest.spec.luau"
check "AC5: zz-review, zz-execute and zz-rules state the final review" \
	lune run tests/run -- "$A/skills.spec.luau"
check "AC6: ./zn final-view builds the limited view for real and refuses a busy folder and an unknown issue" \
	lune run tests/run -- "$A/cli.spec.luau"

finish
