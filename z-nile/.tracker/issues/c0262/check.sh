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
check "AC1: the final review's view is the captured ask, the design from the base with the branch's edits as a patch, the check, the acceptance specs, the skill and the issue's diff; an empty diff refuses" \
	lune run tests/run -- "$A/view.spec.luau"
check "AC2: ./zn done's rule: every member's newest final review must approve, one that did not is BLOCKED for the user and only a newer approving round clears it, and a raft without a grouped record or created before the cutoff is exempt" \
	lune run tests/run -- "$A/gate.spec.luau"
check "AC3: final is a zz-review mode: a prompt that works in the view folder from skill.md with no lessons line, a landing in the raft's folder, the code-review spend phase, the other modes unchanged" \
	lune run tests/run -- "$A/mode.spec.luau"
check "AC4: a final review's findings are harvestable, its files are not item documents, and one leaf module owns the names" \
	lune run tests/run -- "$A/harvest.spec.luau"
check "AC5: full force: the final review resolves through the zz-review table and the review rule that binds it (Opus; grok at xhigh)" \
	lune run tests/run -- "$A/strong.spec.luau"
check "AC6: zz-review, zz-execute and zz-rules state the final review and that a failed one is BLOCKED" \
	lune run tests/run -- "$A/skills.spec.luau"
check "AC7: ./zn final-view and ./zn done, driven for real in a clone: the design comes from the base, the diff is the Touched modules, a busy folder, an unknown issue and an empty diff refuse, done refuses without an approving final review (even if the branch drops the grouped line) and passes with one" \
	lune run tests/run -- "$A/fixture.spec.luau"
check "AC8: ./zn dispatch zz-review --mode final runs the fake CLI in the view folder and lands final-review-<issue>-001.md in the raft's folder; the code review still lands in the issue's" \
	lune run tests/run -- "$A/dispatch.spec.luau"

finish
