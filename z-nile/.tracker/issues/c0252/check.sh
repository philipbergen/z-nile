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
	for s in tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0117/models.spec.luau tests/acceptance/c0117/docs.spec.luau tests/tooling/dispatch-texts.spec.luau tests/tooling/wrapper-guards.spec.luau tests/acceptance/c0239/done.spec.luau tests/tooling/stack-fix.spec.luau tests/tooling/tracker-guarded.spec.luau tests/meta/scanning-loops.spec.luau tests/acceptance/c0193/tree.spec.luau tests/meta/architecture.spec.luau; do
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
	fixtureSpec landcheck --run "AC1: a clean input has no problem, and a draft layer pull request whose only check is SKIPPED is green" "AC1: each failed check is one named problem of its kind" "AC1: a draft layer's UNKNOWN mergeable is not a wait, a merged pull request is closed, and a tracker-only stack needs nothing" "AC1: tracker state is judged by trackerstate, the one definition: a file moved out of an item folder, or under an unregistered .tracker, is code"
}
check "AC1: \`landcheck.problems\` returns one named problem, with its kind (wait, redo or block) and escalation reason, for each failed check: a layer not built or not complete, a final review with no Verdict or not answered, an unruled high finding, a stale trace, approval drift, a stack that changes the gate's own driver, a game stack with no \`cicd.toml\`, a red or waiting clean-clone gate, and a top-layer pull request that is unreadable, closed or merged, in a state it does not know, whose head is not the layer tip, with no check registered, with a check failed, cancelled or still running, or (when it is not a draft) conflicting or with an unknown mergeable; a read that failed (git, the registry) is a wait; a clean input, and a draft layer whose only check was SKIPPED, give none; tracker state is told from code by \`trackerstate\`, the one definition." ac1
ac2() {
	fixtureSpec landcheck "AC2: classify lands a clean input, blocks a block problem at once, and lets a wait wait" "AC2: a problem of a kind the module does not know is a wait, never a landing" "AC2: a redo problem runs the worker again until the cap, then blocks under its own reason" "AC2: only a repeat of the same failure is counted: a worker that moves the codes or the tip starts the count again"
}
check "AC2: \`landcheck.classify\` lands a clean input, blocks a block problem at once, lets a wait wait and never block, reads a problem kind it does not know as a wait, and runs the worker again on a redo problem (a red check included) until \`merge_retries\` repeats of the same failure are spent, then blocks under that problem's reason; a redo outranks a wait, and a worker that changes the failure's codes or the top tip starts the count again." ac2
ac3() {
	fixtureSpec landcheck "AC3: the escalation the dispatcher files parses and names every problem; each code recommends one pinned option, never amend-design" "AC3: the bind is found on main's first-parent line even with tracker commits above it, and a block request round-trips"
}
check "AC3: The \`escalation.md\` the dispatcher files for a block is a note \`escalation.parse\` and \`escalation.check\` accept and names every problem, with the one option each code recommends (\`approve\` for an unruled high finding and approval drift, \`retry\` for the rest, never \`amend-design\`); \`landcheck.findBind\` finds the bind on main's first-parent line among tracker commits and refuses a missing or doubled one; a block request round-trips with the Layer's tip and a malformed one is refused." ac3
ac4() {
	fixtureSpec landcheck "AC4: green is read from the rollup: SKIPPED, NEUTRAL and SUCCESS pass; failed, cancelled and still-running checks are named" "AC4: landread.parsePr reads gh's JSON, and a text it cannot read is a named failure, never a green PR"
}
check "AC4: \"Green\" is read from the pull request's rollup: SUCCESS, NEUTRAL and SKIPPED pass, failed (cancelled, timed out, startup failure included) and still-running (stale and unknown states included) checks are named, and a pull request text that cannot be read, an empty rollup or a missing state is a named failure, never green." ac4
ac5() {
	fixtureSpec dispatch-land --run "AC5: a finished layered raft whose checks pass is landed, through the layer the verdict names" "AC5: with run left out of auto_merge the chain stops at the gate and names the command, and lands nothing" "AC5: a wait stops at the gate with the reasons, a fixable problem runs the worker again as a counted try" "AC5: a verdict of block files a block with its reason and Layer, and a blocked raft stops first" "AC5: a block request lands the green layers below first, then files the block; a red prefix lands nothing" "AC5: an old single-branch raft keeps its pull request and the human's merge, and the lookup of a layered raft is not stale" "AC5: a worker's block request on a raft with no layer branches is filed, not stopped as a run that left a draft" "AC5: a rerun worker is told which checks it runs again for, and a first run is told nothing of the kind"
}
check "AC5: \`dispatch.next\` on an active raft lands a finished raft whose checks pass (through the layer the verdict names), stops at the gate (exit 4) when \`run\` is not in \`auto_merge\` or a check is pending, runs \`z-run\` again as a counted try for a fixable problem and tells that rerun which checks it runs for, files a block for a block verdict, lands the green layers below a requested block first and then files it, waits at the gate with the request kept while those layers' CI runs, never lands a red prefix, and keeps an old single-branch raft's pull request and a human's merge." ac5
ac6() {
	fixtureSpec dispatch-land "AC6: the landing and the block are script steps of the raft's own worktree, with the dispatcher's environment" "AC6: auto_merge takes run, still refuses anything else, and merge_retries is a whole number defaulting to 2"
}
check "AC6: \`z-land\`, \`z-block\` and \`z-gate\` are script steps run in the raft's own worktree; \`models\` accepts \`run\` in \`auto_merge\` (and still refuses any other word) and reads \`merge_retries\` (default 2) and the rerun cap, and no longer knows \`merge_attempts\`." ac6
ac7() {
	fixtureSpec land-cmd --run "AC7: land-check names a pending check as a wait, a failed one as a redo, and passes a green top layer" "AC7: an unreadable pull request, a head that is not the layer tip and a conflict are named, never passed" "AC7: --below names the layers under a Layer: the prefix is judged on its own top, and nothing below the first layer" "AC7: an old single-branch raft gets an explicit no-layers answer, not a problem list"
}
check "AC7: \`./zn land-check <R-id> [--through <issue> | --below <issue>] [--json]\` reads a real raft: a pending check is a wait, a failed one a redo, an unreadable pull request, a head that is not the layer tip, a conflict, a check not yet registered and a mergeable GitHub is still computing are named, a draft layer whose only check was skipped and a green top layer pass with exit 0, \`--below\` judges the layers under a Layer on their own top, and a raft with no layer branches gets an explicit no-layers answer (exit 2)." ac7
ac8() {
	fixtureSpec land-cmd "AC8: in a session that holds the agent's credential, ZN_DISPATCH or ZN_HEADLESS, done runs every check, writes a land request and pushes nothing" "AC8: done refuses every problem the dispatcher would not land on, a wait included, naming the codes, and changes nothing" "AC8: with a green top layer done goes on, and lands the bind"
}
check "AC8: \`./zn done\` in a session that holds the agent's credential (\`ZN_DISPATCH\` or \`ZN_HEADLESS\`) runs every check, writes a land request and pushes nothing, and refuses a failed check there too; in a person's session it refuses every problem the dispatcher would not land on for a person, a wait included (CI running, no check registered, GitHub still computing, a pull request it cannot read), naming the codes and changing nothing, and lands a stack whose top layer is green." ac8
ac9() {
	fixtureSpec land-cmd "AC9: under ZN_DISPATCH, block validates the note and leaves a request for the dispatcher, publishing nothing"
}
check "AC9: Under \`ZN_DISPATCH\`, \`./zn block\` on a raft checks the reason and the note as before, then writes \`block-request\` (with the Layer's published tip) and a copy of the note in the dispatcher's state folder and publishes nothing." ac9
ac10() {
	fixtureSpec land-chain --run "AC10: a finished raft whose top layer is green is landed by the dispatcher with its own environment: one bind, the raft done, exit 0"
}
check "AC10: \`./zn dispatch <R-id>\` lands a finished raft whose top layer is green with the dispatcher's own environment (the user's credential, no \`ZN_DISPATCH\`, no \`ZN_HEADLESS\`): one \`--no-ff\` bind on \`origin/main\`, the raft in \`done/\`, exit 0, and a second run finds it done." ac10
ac11() {
	fixtureSpec land-chain "AC11: a pending check stops the chain at the gate with exit 4 and the reason, and lands nothing" "AC11: a failure the worker can fix runs it again twice with the checks named in its prompt, then the raft blocks under red-gate with a note that recommends retry" "AC11: a failed check is a fixable problem too: the worker runs again twice, then the raft blocks, the dispatcher files the note and runs block, and exits 3" "AC11: a land-check that prints garbage is a wait (exit 4) and nothing is landed" "AC11: a worker that fixes one failure per run is not capped by the count: it lands after more reruns than merge_retries"
}
check "AC11: The chain stops at the gate (exit 4) with the reason on a pending check and lands nothing; on a failure the worker can fix (a head that is not the tip, a failed check) it runs the worker again twice with the checks named in its prompt and then blocks under the problem's reason, filing an \`escalation.md\` that parses, names the problems and recommends \`retry\`, and exits 3; an answer from \`land-check\` that is not an answer is a wait and lands nothing; a worker that fixes a different failure each run is not capped by the count." ac11
ac12() {
	fixtureSpec land-chain "AC12: a requested block waits at the gate while the green layers below still have CI running, then lands them first and files the block with the Layer's open findings and the worker's committed note" "AC12: a worker's uncommitted note is put back on the Layer's tip when the block is filed after the green layers below landed"
}
check "AC12: A block the worker requests lands the green layers below the Layer first (\`done --through\`), after waiting at the gate while their CI runs, then files the block on the Layer's tip with the worker's own note, committed on the layer or not, and the Layer's open finding ids, and the raft is left blocked." ac12
ac13() {
	fixtureSpec docs --run "AC13: zz-rules Dispatch: the chain judges and lands a finished raft with the base's engine, gates a game stack in a clean clone, and names the run gate" "AC13: zz-execute Phase 6 and z-run Headless: a worker stops after its work, never runs done, and blocks by request" "AC13: the README marks the dispatcher's landing as existing and keeps the person-approval clause the scope decision asks for" "AC13: the root .models.toml arms the run gate and names merge_retries, and the step prompt tells a worker what done does and a rerun why it runs"
}
check "AC13: zz-rules, zz-execute, every headless skill section, the README, the root \`.models.toml\` and the step prompt say that the dispatcher judges and lands a green stack with the base's engine and \`./zn done\` after its checks, that \`done\` in an agent-credential session leaves a land request for a lander, that a worker's block is a request, and that a rerun is told why it runs; the README keeps the person-approval clause (\`once a person has approved its design\`, \`stops at a person's ./zn approve\`)." ac13
ac14() {
	fixtureSpec land-chain "AC14: after the dispatcher's own bind the guard's mark moves to it, so main is vetted; tracker commits other sessions published after the bind do not trip it, and a foreign commit still does"
}
check "AC14: After the dispatcher's own bind the guard's mark moves to it (\`dispatcher.afterLand\`), so the next \`vetMain\` is clean even when other sessions published tracker commits after the push; a main history that does not hold the bind, and a foreign code commit beside it, still trip it." ac14
ac15() {
	runRegression
}
check "AC15: The promoted specs of the dispatcher, the models, the wrapper guards, \`done\`, the loop rules and the skills' shared sections still pass (the fast ones; the slow ones are named in Implementation steps)." ac15
ac16() {
	fixtureSpec land-chain "AC16: after the layers finish, main gains a tracker commit and a non-conflicting code commit, and the dispatcher still lands one bind"
}
check "AC16: After the layers finish, \`main\` gains a tracker commit and a code commit that does not conflict, and the dispatcher still lands one bind and keeps both commits." ac16
ac17() {
	fixtureSpec land-cmd "AC17: zn -C runs this checkout's engine against another worktree of the same repository and refuses a directory of another repository"
	fixtureSpec land-chain "AC17: a layer that rewrites landcheck.luau so that it finds no problem does not judge its own landing: the base's engine still files the failed check" "AC17: the bind is made by the base's engine: a layer that changes how its own raft's bind is worded does not get its wording" "AC17: a stack that changes the gate's own driver is a wait for a person (self-gating), whatever its checks say"
}
check "AC17: The landing is judged and performed by the base's engine: a layer that rewrites \`landcheck.luau\` so that it finds no problem does not judge its own landing, a layer that rewrites how its own raft's bind is worded does not get its wording, a stack that changes the gate's own driver is a wait for a person, and \`zn -C\` runs this checkout's engine only against a worktree of the same repository." ac17
ac18() {
	fixtureSpec land-chain "AC18: a game stack waits without cicd.toml and while a cicd lease is held, and lands after the clean-clone full gate and the cicd run pass on the bind's tree" "AC18: a red clean-clone full gate is a failure the worker can fix: it runs again twice and the raft then blocks under red-gate, landing nothing"
}
check "AC18: A stack that changes a game waits (exit 4) without \`cicd.toml\` and while a cicd lease is held, lands only after the clean-clone full gate and the cicd run pass on the tree the bind would make, and a red full gate is a failure the worker can fix that blocks after the retries and lands nothing." ac18
ac19() {
	fixtureSpec land-chain "AC19: an old single-branch raft with an open pull request keeps its human's merge end to end: the chain stops at it without running the worker"
}
check "AC19: An old single-branch raft with an open pull request keeps a human's merge end to end: the chain stops at it without running the worker." ac19
ac20() {
	fixtureSpec landcheck "AC20: a land request round-trips with the raft, the tip, --through and the worktree, a malformed one is refused, and only the same tip is fresh"
	fixtureSpec land-chain "AC20: a worker's land request waits (nothing lands, nothing is pushed) until a lander lands it with its own environment, and the request is spent" "AC20: the dispatcher's landing of a raft spends the land request the worker left for it"
}
check "AC20: A land request carries the raft, the layer tip, \`--through\` and the worktree, and waits:  with no lander nothing lands and nothing is pushed; \`./zn lander\` lands it through the base's engine with its own environment (the user's credential, no agent marker) and spends the request, and the dispatcher's landing of the raft spends it too." ac20
ac21() {
	fixtureSpec land-cmd "AC21: the lander is refused in a session that holds the agent's credential, and with no request it lands nothing"
	fixtureSpec land-chain "AC21: a land request whose layer tip moved is refused and spent, and the worker asks again"
}
check "AC21: A land request whose layer tip moved since the worker's checks is refused and spent, and \`./zn lander\` is refused in a session that holds the agent's credential, and lands nothing when no request waits." ac21

finish
