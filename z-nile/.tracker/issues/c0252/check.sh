#!/usr/bin/env bash
# Acceptance checks for c0252. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0252 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0252"

# landcheck.spec and dispatch-land.spec are plain specs. land-cmd.spec drives the real ./zn on a two-layer raft in a
# fixture under .cache (a local github-shaped origin, a gh stub that answers `pr view --json statusCheckRollup` from a
# file per layer branch), land-chain.spec drives `./zn dispatch` against fake CLIs and the same stub over four rafts, and
# docs.spec reads the skills, the README and the root .models.toml. Their cases build on each other, so each runs once,
# and every criterion then checks that each of its own cases passed: the runner writes each passing case's name to the
# --out file, but only when the whole run passes (z-nile/specs.luau), so one red case leaves the record empty and every
# criterion of that spec reports it (lesson zz-test/out-records-only-a-green-run): read the run's FAIL lines.
OUT="$PWD/.cache/c0252-check"
fixtureSpec() {
	local file="$1" home rel out
	shift
	home="$(pwd -P)"
	rel="${A#"$home"/}/$file.spec.luau" # the runner takes the spec's path from the project home
	out="$OUT/$file.txt"
	if [[ ${1:-} == --run ]]; then
		shift
		mkdir -p "$OUT" && : >"$out" # an empty record when no case passes: each criterion then names the case that did not
		# the runner reads the project registry from the repository root
		(cd "$(git rev-parse --show-toplevel)" && lune run "$home/specs" -- run --project z-nile --out "$out" -- "$rel") || true
	fi
	[[ -f $out ]] || { echo "$file.spec did not run"; return 1; }
	local c
	for c in "$@"; do
		grep -qxF "	$c" "$out" || { echo "did not pass: $c (or another case of $file.spec failed: the record is written only for a green run, so read its FAIL lines)"; return 1; }
	done
}

# AC15: the existing specs the landing and the dispatcher stand on, of the listed ones those not in the measured slow
# tier (tests/slow.tsv). The slow tier is the gate's, run by Implementation step 11, never by this check.sh.
regressionSpecs() {
	local s
	for s in tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0117/models.spec.luau tests/acceptance/c0117/docs.spec.luau tests/tooling/dispatch-texts.spec.luau tests/tooling/wrapper-guards.spec.luau tests/acceptance/c0239/done.spec.luau tests/tooling/stack-fix.spec.luau tests/meta/scanning-loops.spec.luau tests/acceptance/c0193/tree.spec.luau tests/meta/architecture.spec.luau; do
		grep -qF "	$s" tests/slow.tsv || printf '%s\n' "$s"
	done
}
runRegression() {
	local list
	list=$(regressionSpecs)
	[[ -n $list ]] || { echo "no regression spec is listed"; return 1; }
	# shellcheck disable=SC2086 # one spec path per word
	lune run tests/run -- $list
}

ac1() {
	fixtureSpec landcheck --run "AC1: a clean input has no problem, and a draft layer pull request whose only check is SKIPPED is green" "AC1: each failed check is one named problem of its kind" "AC1: a game path with cicd present, and a tracker path in a game home, need nothing" "AC1: only code main gained is a problem; tracker state main gained is not (c0152)"
}
check "AC1: \`landcheck.problems\` returns one named problem, with its kind (wait, redo or block) and escalation reason, for each failed check: a layer not complete, a final review with no Verdict or not answered, an unruled high finding, a stale trace, approval drift, code gained by \`main\` since the stack's base (tracker state gained is not), a game stack with no \`cicd.toml\`, and a top-layer pull request that is unreadable, closed, whose head is not the layer tip, that conflicts, whose check failed or is still running; a clean input, and a draft layer whose only check was SKIPPED, give none." ac1
ac2() {
	fixtureSpec landcheck "AC2: classify lands a clean input, blocks a block problem at once, and lets a wait wait" "AC2: a redo problem runs the worker again until the cap, then blocks under its own reason"
}
check "AC2: \`landcheck.classify\` lands a clean input, blocks a block problem at once, lets a wait wait and never block, and runs the worker again on a redo problem until \`merge_attempts\` tries are spent and then blocks under that problem's reason; a redo outranks a wait." ac2
ac3() {
	fixtureSpec landcheck "AC3: the escalation the dispatcher files parses, has one recommended option and names every problem" "AC3: the dispatcher's own bind is a merge whose second parent is the layer tip, and a block request round-trips"
}
check "AC3: The \`escalation.md\` the dispatcher files for a block is a note \`escalation.parse\` and \`escalation.check\` accept, with one recommended option and every problem named; \`landcheck.ownBind\` accepts only a merge whose second parent is the layer tip; a block request round-trips and a malformed one is refused." ac3
ac4() {
	fixtureSpec landcheck "AC4: green is read from the rollup: SKIPPED, NEUTRAL and SUCCESS pass; failed and still-running checks are named" "AC4: landread.parsePr reads gh's JSON, and a text it cannot read is a named failure, never a green PR"
}
check "AC4: \"Green\" is read from the pull request's rollup: SUCCESS, NEUTRAL and SKIPPED pass, failed and still-running checks are named, and a pull request text that cannot be read is a named failure, never green." ac4
ac5() {
	fixtureSpec dispatch-land --run "AC5: a finished layered raft whose checks pass is landed, through the layer the verdict names" "AC5: with run left out of auto_merge the chain stops at the gate and names the command, and lands nothing" "AC5: a wait stops at the gate with the reasons, a fixable problem runs the worker again as a counted try" "AC5: a verdict of block files a block with its reason and Layer, and a blocked raft stops first" "AC5: a block request lands the green layers below first, then files the block; a red prefix lands nothing" "AC5: an old single-branch raft keeps its pull request and the human's merge, and the lookup of a layered raft is not stale"
}
check "AC5: \`dispatch.next\` on an active raft lands a finished raft whose checks pass (through the layer the verdict names), stops at the gate (exit 4) when \`run\` is not in \`auto_merge\` or a check is pending, runs \`z-run\` again as a counted try for a fixable problem, files a block for a block verdict, lands the green layers below a requested block first and then files it, never lands a red prefix, and keeps an old single-branch raft's pull request and a human's merge." ac5
ac6() {
	fixtureSpec dispatch-land "AC6: the landing and the block are script steps of the raft's own worktree, with the dispatcher's environment" "AC6: auto_merge takes run, still refuses anything else, and merge_attempts is a whole number defaulting to 2"
}
check "AC6: \`z-land\` and \`z-block\` are script steps run in the raft's own worktree; \`models\` accepts \`run\` in \`auto_merge\` (and still refuses any other word) and reads \`merge_attempts\` (default 2)." ac6
ac7() {
	fixtureSpec land-cmd --run "AC7: land-check names a pending check as a wait, a failed one as a block, and passes a green top layer" "AC7: an unreadable pull request, a head that is not the layer tip and a conflict are named, never passed" "AC7: --below names the layers under a Layer: the prefix is judged on its own top, and nothing below the first layer"
}
check "AC7: \`./zn land-check <R-id> [--through <issue> | --below <issue>] [--json]\` reads a real raft: a pending check is a wait, a failed one a block, an unreadable pull request, a head that is not the layer tip and a conflict are named, a green top layer passes with exit 0, and \`--below\` judges the layers under a Layer on their own top." ac7
ac8() {
	fixtureSpec land-cmd "AC8: done is refused while ZN_DISPATCH is set, and lands nothing" "AC8: done refuses a stack whose top layer has a failed check, naming the code, and changes nothing" "AC8: a check still running is a person's to judge: done goes on, and lands the bind"
}
check "AC8: \`./zn done\` is refused while \`ZN_DISPATCH\` is set, refuses a stack whose top layer has a failed check (naming the code, changing nothing), and goes on past a check that is still running, which is a person's to judge." ac8
ac9() {
	fixtureSpec land-cmd "AC9: under ZN_DISPATCH, block validates the note and leaves a request for the dispatcher, publishing nothing"
}
check "AC9: Under \`ZN_DISPATCH\`, \`./zn block\` on a raft checks the reason and the note as before, then writes \`block-request\` in the dispatcher's state folder and publishes nothing." ac9
ac10() {
	fixtureSpec land-chain --run "AC10: a finished raft whose top layer is green is landed by the dispatcher: one bind, the raft done, exit 0"
}
check "AC10: \`./zn dispatch <R-id>\` lands a finished raft whose top layer is green: one \`--no-ff\` bind on \`origin/main\`, the raft in \`done/\`, exit 0, and a second run finds it done." ac10
ac11() {
	fixtureSpec land-chain "AC11: a pending check stops the chain at the gate with exit 4 and the reason, and lands nothing" "AC11: a problem the worker can fix runs it again twice, then blocks under its reason" "AC11: a failed check blocks the raft at once: the dispatcher files the note, runs block, and exits 3"
}
check "AC11: The chain stops at the gate (exit 4) with the reason on a pending check and lands nothing; it blocks at once on a failed check; on a fixable problem it runs the worker again twice and then blocks under the problem's reason; each block files an \`escalation.md\` that parses and names the problems, and the chain exits 3." ac11
ac12() {
	fixtureSpec land-chain "AC12: a requested block lands the green layers below it first, then files the block"
}
check "AC12: A block the worker requests lands the green layers below the Layer first (\`done --through\`), then files the block, and the raft is left blocked with the worker's own note." ac12
ac13() {
	fixtureSpec docs --run "AC13: zz-rules Dispatch: the chain lands a finished raft through land-check and done, and names the run gate" "AC13: zz-execute Phase 6 and z-run Headless: a worker stops after its work, never runs done, and blocks by request" "AC13: the README marks the dispatcher's landing as existing, and keeps the person-approval clause" "AC13: the root .models.toml arms the run gate and names merge_attempts, and the step prompt tells a worker done is refused"
}
check "AC13: zz-rules, zz-execute, every headless skill section, the README, the root \`.models.toml\` and the step prompt say that the dispatcher lands a green stack with \`./zn done\` after its checks, that \`done\` is refused for a worker, and that a worker's block is a request." ac13
ac14() {
	fixtureSpec land-chain "AC14: after the dispatcher's own bind the guard's mark moves to it, so main is vetted, and a foreign commit still trips"
}
check "AC14: After the dispatcher's own bind the guard's mark moves to it (\`dispatcher.afterLand\`), so the next \`vetMain\` is clean; a main tip that is not that bind, and a foreign commit, still trip it." ac14
ac15() {
	runRegression
}
check "AC15: The promoted specs of the dispatcher, the models, the wrapper guards, \`done\`, the loop rules and the skills' shared sections still pass (the fast ones; the slow ones are named in Implementation steps)." ac15

finish
