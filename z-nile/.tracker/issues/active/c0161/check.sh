#!/usr/bin/env bash
# Acceptance checks for c0161. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0161 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0161"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: status <id> prepared refuses an issue with no approving design review round that quotes the design as it is (a closure, a design changed after its approving round, a scope reset in place, a reclaimed issue, a newest round that says changes), and passes an approving one (committed or not)" \
	lune run tests/run -- "$A/review-gate.spec.luau"
check "AC2: the pure rule reads the newest round: a missing round, a missing or misspelled Verdict, changes, and a missing or different Design record are problems naming the file" \
	lune run tests/run -- "$A/review-rule.spec.luau"
check "AC3: a raft's carried move asks the same of every preparing issue it takes (its own folder's approving round; the raft's folder is no stand-in) and nothing of a prepared one" \
	lune run tests/run -- "$A/review-raft.spec.luau"
check "AC4: z-design, the defect checklist, zz-review, zz-rules and z-raft say it" \
	lune run tests/run -- "$A/docs.spec.luau"
check "AC5: the five promoted specs whose fixtures prepare an issue carry their rounds now and still pass" \
	lune run tests/run -- tests/acceptance/c0053/commands-claim.spec.luau tests/acceptance/c0053/commands-prep.spec.luau tests/acceptance/c0053/commands-start.spec.luau tests/acceptance/c0116/claims.spec.luau tests/acceptance/c0116/issue-design.spec.luau
check "AC6: ./zn design-record prints the record (document, check.sh, acceptance, experiments; not reviews or what the process writes) and a renumber re-records the lines that matched, before grouped:" \
	lune run tests/run -- "$A/design-record.spec.luau"
check "AC7: new raft, fold, recombine and ready refuse a prepared issue edited after its quoted round and take a matching one, raft-plan skips it, and an issue no round of which quotes a record is exempt" \
	lune run tests/run -- "$A/review-read.spec.luau"

finish
