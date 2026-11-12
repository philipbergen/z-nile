#!/usr/bin/env bash
# Acceptance checks for c0248. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0248 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0248"

# A spec file holds the cases of several criteria; each case's label starts with its ACn. completion.spec is pure;
# layers-land.spec drives real git in a fixture under .cache (a local bare origin and a gh stub); dispatch-review.spec
# drives `./zn dispatch` with fake CLIs under .cache; docs.spec reads the skills, templates and README.
check "AC1: a layer with no review in its issue folder is not complete (completion.layer)" lune run tests/run -- "$A/completion.spec.luau"
check "AC2: a layer whose newest review has no Verdict line, or a finding not answered by the final review's rules (one shared function, reading the issue document's open list), is not complete" lune run tests/run -- "$A/completion.spec.luau"
check "AC3: a layer is complete only when its review is current (its Commit, or its Patch, is the finish commit's, or a refute with a fixed answer carries it); a missing stamp is not complete" lune run tests/run -- "$A/completion.spec.luau"
# layers-land.spec drives real git in a fixture and its cases build on each other, so it runs once (AC4) and each
# criterion then checks that every one of its own cases passed: the runner writes each passing case's name to $OUT.
OUT="$PWD/.cache/c0248-check/layers-land.txt"
layers() {
	local home rel
	home="$(pwd -P)"
	rel="${A#"$home"/}/layers-land.spec.luau" # the runner takes the spec's path from the project home
	if [[ ${1:-} == --run ]]; then
		shift
		mkdir -p "${OUT%/*}" && rm -f "$OUT"
		# the runner reads the project registry from the repository root
		(cd "$(git rev-parse --show-toplevel)" && lune run "$home/specs" -- run --project z-nile --out "$OUT" -- "$rel") || true
	fi
	[[ -f $OUT ]] || { echo "layers-land.spec did not run"; return 1; }
	local c
	for c in "$@"; do
		grep -qxF "	$c" "$OUT" || { echo "did not pass: $c"; return 1; }
	done
}
check "AC4: ./zn commit stamps a new layer review or refute in the issue folder with the finish commit and its patch id and refuses one on an unfinished layer, and a review committed after finish keeps the layer finished" layers --run 'AC4: ./zn commit stamps a new review in the issue folder with the finish commit and its patch, and refuses one on an unfinished layer' 'AC4: a review committed in the issue folder after finish keeps the layer finished'
check "AC5: ./zn start opens the next layer only when the layer below is complete; ./zn done refuses any layer not complete, the top one included, lands the same bind as before for a complete stack, lands with no new reviews after main moves and a restack, and refuses after a restack that changes a layer's patch" layers 'AC5: start refuses the next layer until the layer below is complete, naming it, and opens it once the review is settled' 'AC5: done refuses a stack whose top layer is not complete' 'AC5: a full done of complete layers lands the same bind as #296' 'AC5: main moves, restack, done lands with no new review files' 'AC5: a restack whose conflict resolution changes a layer'\''s patch leaves it not complete, naming both commits'
check "AC6: ./zn done <R> --through <issue> lands only the layers up to that issue's with its own final-review-NNN and trace-NNN, moves only those members, keeps the raft active, retargets the landed PRs and the next layer's to main, and runs the raft's check.sh scoped to the landing (members, promote-check) with RC1 and up skipped until the last landing" layers 'AC6: done --through lands only the layers up to the named one with its own final-review-NNN and trace-NNN, moves only them, keeps the raft active, retargets the next PR to main' 'AC6: on a raft whose check.sh is the rendered template and whose third member'\''s check.sh fails, done --through c0150 lands, members prints two folders, RC1 is skipped, and a full done refuses'
check "AC7: ./zn done --through refuses a HEAD that is not that layer's published tip, an id that is not a member or is already landed, and an incomplete layer in the range" layers 'AC7: done --through refuses a HEAD that is not that layer'\''s tip, an id that is not a member or already landed, an incomplete layer'
check "AC8: in the decided order the layer above a landing is restacked onto main, keeps a current review when its patch is unchanged, and the second landing lands with its own final review and trace and moves the raft, whether the landed branches were kept or deleted; ./zn stack shows the landed layers" layers 'AC8: in the decided order (layer 3 exists, then layers 1-2 land), restack moves layer 3 onto main, its review stays current, and the second landing lands with its own final review and trace and moves the raft (landed branches kept)' 'AC8: the same with the landed branches deleted from origin'
check "AC9: a partly landed raft that is stopped and readied again keeps its landed members, and start opens the next layer above them" layers 'AC9: after an early landing, stop and ready keep the landed members and start opens the next layer above them'
check "AC10: ./zn dispatch zz-review <issue> --mode code files a stamped review into the issue folder and refuses an unfinished layer; --mode final --through files the next final-review-NNN.md and trace-NNN.md, and each landing gets one final review" lune run tests/run -- "$A/dispatch-review.spec.luau"
check "AC11: a raft readied without layers: reviewed keeps today's rule; ./zn ready writes the marker" layers 'AC11: a raft readied without the marker keeps today'\''s rule; ready writes layers: reviewed'
check "AC12: every layer's PR body names the raft's Theme, its Order and the stack, rewritten by start, finish, restack and done; a failed edit only warns" layers 'AC12: every layer PR body names the raft'\''s Theme, Order and the stack, rewritten by start, finish, restack and done, and a failed edit only warns'
check "AC13: zz-execute, zz-rules, zz-review, z-run, the prompt template and the raft template say one worker builds the layers in order, each complete before the next, a second machine only through a takeover, a layer's open list and harvest in the issue's documents, a final review per landing, and done --through below a block" lune run tests/run -- "$A/docs.spec.luau"
check "AC14: the README's Stacked delivery describes the one bind and is exists (c0248), its Roadmap row for c0248 is exists, c0248 to c0254 are one raft, and no bottom-up is left" lune run tests/run -- "$A/docs.spec.luau"
# the fast stack specs only: of the listed specs, those not in the measured slow tier (tests/slow.tsv). The slow tier
# is the gate's, run by Implementation step 12 (z-nile/check.sh --slow), never by this check.sh.
fastSpecs() {
	local s
	for s in tests/tooling/stack.spec.luau tests/tooling/stack-fix.spec.luau tests/tooling/trace.spec.luau tests/tooling/trace-land.spec.luau tests/tooling/start-pr-reuse.spec.luau tests/acceptance/c0074/done-gate.spec.luau tests/acceptance/c0117/docs.spec.luau tests/acceptance/c0120/promote-home.spec.luau; do
		grep -qF "	$s" tests/slow.tsv || printf '%s\n' "$s"
	done
}
runFast() {
	local list
	list=$(fastSpecs)
	[[ -n $list ]] || { echo "no fast stack spec is listed"; return 1; }
	# shellcheck disable=SC2086 # one spec path per word
	lune run tests/run -- $list
}
check "AC15: the fast stack specs (stack, stack-fix, trace, trace-land, start-pr-reuse, c0074/done-gate, c0117/docs, c0120/promote-home, those not in tests/slow.tsv) still pass" runFast

finish
