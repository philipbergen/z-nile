#!/usr/bin/env bash
# Acceptance checks for c0306. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0306 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0306"

# reviewmodel.spec, publish.spec, ready.spec and docs.spec are plain specs. commands.spec drives the real ./zn in a
# fixture under .cache (a local bare origin whose path contains github.com, a prep worktree, a gh stub that records its
# calls, a raft worktree), done.spec drives `./zn commit` and `./zn done` in three offline fixtures (as c0084's spec does)
# and dispatch-review.spec drives `./zn dispatch zz-review` against fake CLIs. Their cases build on each other, so each
# runs once, and every criterion then checks that each of its own cases passed: the runner writes each passing case's
# name to the --out file, but only when the whole run passes (z-nile/specs.luau), so one red case leaves the record empty
# and every criterion of that spec reports it (lesson zz-test/out-records-only-a-green-run): read the run's FAIL lines.
OUT="$PWD/.cache/c0306-check"
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

# the fast specs this change touches: of the listed specs, those not in the measured slow tier (tests/slow.tsv). The slow
# tier is the gate's, run by Implementation step 10 (z-nile/check.sh --slow), never by this check.sh.
fastSpecs() {
	local s
	for s in tests/acceptance/c0043/review-skill.spec.luau tests/acceptance/c0052/skill-doc.spec.luau tests/acceptance/c0053/status.spec.luau tests/acceptance/c0067/paths.spec.luau tests/acceptance/c0081/publish-guard.spec.luau tests/acceptance/c0082/audit.spec.luau tests/acceptance/c0084/ledger.spec.luau tests/acceptance/c0111/skill-docs.spec.luau tests/acceptance/c0114/docs.spec.luau tests/acceptance/c0115/docs.spec.luau tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0116/plan.spec.luau tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0117/docs.spec.luau tests/acceptance/c0117/models.spec.luau tests/acceptance/c0118/model.spec.luau tests/acceptance/c0120/docs.spec.luau tests/acceptance/c0184/docs.spec.luau tests/acceptance/c0191/docs.spec.luau tests/acceptance/c0239/docs.spec.luau tests/acceptance/c0239/done.spec.luau tests/tooling/dispatch-texts.spec.luau tests/tooling/openlist.spec.luau tests/tooling/raftcheck.spec.luau tests/tooling/readycheck.spec.luau tests/tooling/work.spec.luau; do
		grep -qF "	$s" tests/slow.tsv || printf '%s\n' "$s"
	done
}
runFast() {
	local list
	list=$(fastSpecs)
	[[ -n $list ]] || { echo "no fast spec is listed"; return 1; }
	# shellcheck disable=SC2086 # one spec path per word
	lune run tests/run -- $list
}

# AC11: a text check, no spec run (the slow tier is the gate's): each spec on the Overrides line, and the tooling spec
# watch-map, gives the reviews it writes by hand the record the rule needs, a `Model: claude-opus-5-5` line or
# `--model claude-opus-5-5` on the commit or spend that records it. Each of today's files (origin/main) has neither.
ac11() {
	local f bad=0
	for f in tests/acceptance/c0001/tracker-lifecycle.spec.luau tests/acceptance/c0008/done-order.spec.luau tests/acceptance/c0038/deferred.spec.luau tests/acceptance/c0074/done-gate.spec.luau tests/acceptance/c0080/consequences.spec.luau tests/acceptance/c0084/commit-phase.spec.luau tests/acceptance/c0084/spend-command.spec.luau tests/acceptance/c0116/claims.spec.luau tests/acceptance/c0116/issue-design.spec.luau tests/acceptance/c0120/promote-home.spec.luau tests/tooling/watch-map.spec.luau; do
		perl -0ne 'exit(/Model: claude-opus-5-5|--model["\s,]+claude-opus-5-5/ ? 0 : 1)' "$f" || { echo "no review in $f has a record: add a Model: claude-opus-5-5 line or --model claude-opus-5-5"; bad=1; }
	done
	return $bad
}

ac1() {
	fixtureSpec reviewmodel --run "AC1: ok passes claude-opus-, claude-fable- and kimi-code-k3 ids at any effort" "AC1: ok passes a grok- id only at effort xhigh and refuses it with no effort" "AC1: ok refuses every other id, the aliases opus and claude-opus included, and judges the prefix plainly" "AC1: describe names the four kinds"
}
check "AC1: \`reviewmodel.ok\` passes \`claude-opus-\`, \`claude-fable-\` and \`kimi-code-k3\` ids at any effort and \`grok-\` ids only at \`xhigh\`, refuses every other id and a \`grok-\` id with no effort, and \`describe\` names the four kinds." ac1
ac2() {
	fixtureSpec reviewmodel "AC2: stamp prepends Model: and Effort: to a review that records none" "AC2: stamp leaves out Effort: when none is given" "AC2: stamp refuses a review that already records a model, whether the new value differs or not" "AC2: read finds both lines within the first 12 lines, beside c0248's Commit: and Patch:" "AC2: read gives nil for a review with no record, and an empty string for a Model: line with no id" "AC2: a stamped review reads back what was stamped"
}
check "AC2: \`reviewmodel.stamp\` prepends \`Model:\` and \`Effort:\` to a review with none, leaves out \`Effort:\` when none is given, refuses a review that already records a model, and \`read\` finds both lines within the first 12 lines beside c0248's \`Commit:\` and \`Patch:\`." ac2
ac3() {
	fixtureSpec publish --run "AC3: a claim (status preparing) may add reviews: judged to an existing issue" "AC3: a new raft's document may carry the line, and a document without it is untouched" "AC3: the line is refused on any other status move of an existing document" "AC3: the line is refused on a document that is not an issue's, or whose claim is a raft's" "AC3: the line is refused in a new issue's stub" "AC3: the line is never removed or changed, in a claim or out of it" "AC3: a status line in the body is not a claim, and a mark line in the body is not the mark" "AC3: publish and the commands read the mark the same way: a trailing space is a mark in both" && \
	fixtureSpec commands --run "AC3: status preparing writes reviews: judged into an issue with no design review, in the claim's one commit" "AC3: status preparing leaves an issue that has a design review unmarked" "AC3: new raft writes reviews: judged into the raft and not into its members" "AC3: the local new raft writes reviews: judged into the raft it makes"
}
check "AC3: \`./zn status <id> preparing\` writes \`reviews: judged\` into an issue with no design review and not into one that has one, both forms of \`./zn new raft\` write it into the raft, and the published claim passes \`publish.luau\`, which refuses the line in any other commit." ac3
ac4() {
	fixtureSpec commands "AC4: status prepared refuses a marked issue whose design review records a model that is not a review model, naming the file, the model and the four kinds" "AC4: status prepared refuses a marked issue whose design review records no Model: line" "AC4: status prepared's refusal of an off-model record names only a new round, and of a missing record also the spend that records it" "AC4: only the newest round is judged: a later round on a review model clears an earlier cheap one, and a later cheap round is refused" "AC4: following status prepared's refusal to a pass: a new round, recorded with the spend the refusal names" "AC4: status prepared passes a marked issue on each review kind" "AC4: status prepared refuses grok- below xhigh and with no effort" "AC4: status prepared passes an unmarked issue on any review, and does not refuse a marked issue with no design review" "AC4: status prepared on a raft does not judge its coherence review: ready does"
}
check "AC4: \`./zn status <id> prepared\` refuses a marked issue whose design review records a model that is not a review model, or no \`Model:\` line, naming the file, the recorded model, the four kinds and only the ways out that work from there, and passes one on each review kind; only the newest round is judged, so a later round on a review model clears an earlier cheap one and a later cheap round is refused; an unmarked issue passes any review; an issue with no design review is not refused." ac4
ac5() {
	fixtureSpec ready --run "AC5: a marked raft whose coherence review is off the review models is refused, naming the file and the model" "AC5: a marked raft whose coherence review records no model is refused (omission never passes)" "AC5: a coherence review's refusal says its way out is made in a worktree and lands by pull request" "AC5: only the newest round of the coherence review is judged: a later round on a review model clears an earlier cheap one, and a later cheap round is refused" "AC5: a marked member's design review off the review models is refused, naming the member" "AC5: a marked raft and member on a review model pass, at every kind" "AC5: an unmarked raft and member pass any review, and a marked raft with no review is not refused" && \
	fixtureSpec commands "AC5: ./zn ready and ./zn work next refuse a marked raft whose coherence review is off the review models" "AC5: ./zn ready and ./zn work next refuse a marked raft whose member's design review is off the review models, naming the member" "AC5: ./zn ready and ./zn work next refuse a marked raft whose coherence review records no model" "AC5: an unmarked raft, and a marked raft on a review model, are readied" "AC5: following ready's refusal to a pass: a new coherence round, recorded in a worktree and landed, clears it" "AC5: following work next's refusal to a pass: the same new round clears it"
}
check "AC5: \`./zn ready <R-id>\` and \`./zn work next\` refuse a marked raft whose newest coherence review, or a marked member's newest design review, is not on a review model, and a later round on one clears it; an unmarked raft passes." ac5
ac6() {
	fixtureSpec ready "AC6: work.decide prints the codeModel refusal where it would say to run ./zn done, and only there" && \
	fixtureSpec commands "AC6: work next says to run done for a raft whose reviews are on review models, and names the refusal for a marked raft whose final review is not" "AC6: work next says to run done for an unmarked raft whose final review is on claude-sonnet-5-5" && \
	fixtureSpec done --run "AC6: done passes an unmarked raft whose reviews record claude-sonnet-5-5" "AC6: done refuses a marked raft whose final review is not on a review model, naming the file and the model" "AC6: done's refusal names only a new round, committed with --phase code-review --model" "AC6: only the newest review-NNN and the newest final-review-NNN are judged: a later round on a review model clears an earlier cheap one, and a later cheap round is refused" "AC6: done never judges a stream review or a refute, and passes a marked raft whose reviews are on review models" "AC6: done judges the review files in a member's folder too (a third fixture: a marked raft with a layer review there)" "AC6: following done's refusal to a pass: a new final round, committed with the command the refusal names, clears it"
}
check "AC6: \`./zn done <R-id>\` refuses a marked raft whose newest \`review-NNN.md\` or newest \`final-review-NNN.md\`, in the raft folder or a member's folder, is not on a review model or records none, while a later round on one clears it, never judges a stream review, and passes one on a review model; \`./zn work next\` names the refusal instead of \`./zn done\`; an unmarked raft passes." ac6
ac7() {
	fixtureSpec dispatch-review --run "AC7: a design review is stamped with the design-challenge role's model and effort" "AC7: a raft review is stamped with the raft role's model and effort" "AC7: a code review is stamped with the code-review role's model and effort" "AC7: a code review that a fallback wrote is stamped with the fallback's model, the one that wrote it" "AC7: a final review is stamped with the final-review role's model, and no Effort: line when the role names none" "AC7: a stream review is stamped too" "AC7: a reviewer that writes its own Model: line fails the step and files nothing" "AC7: in an unmarked item, a reviewer's own Model: line is filed as written" "AC7: in a marked item, a newest design review off the review models is superseded: the dispatcher files design-review-002, stamped" "AC7: in a marked item, a newest review on a review model keeps the one-round refusal" "AC7: in an unmarked item, a cheap review keeps the one-round refusal as today" "AC7: in a marked item, a cheap code review is superseded too: review-002, stamped" "AC7: in a marked item, a try the rule refuses is never started and the next try is: grok at high is skipped for the agent" "AC7: in a marked item with no try on a review model, the step fails up front, naming the role" "AC7: in an unmarked item, grok at high is tried as today" "AC7: a stream review is not held to the review models: grok at high runs in a marked item"
}
check "AC7: the dispatcher stamps \`Model:\` and \`Effort:\` from the spec of the attempt that wrote it into every review it files (design, raft, code, final and stream modes), and in a marked item fails a step whose reviewer wrote its own \`Model:\` line, skips a try the rule would refuse (failing when none is left), and files a new round of a kind at the next number only when the newest one is refused." ac7
ac8() {
	fixtureSpec reviewmodel "AC8: ledger.isModel accepts claude-opus-5-5[1m] and still refuses a space and a cell separator" && \
	fixtureSpec commands "AC8: spend --phase design-review is refused without --model, naming the flag, and stamps nothing" "AC8: an unmarked issue's spend --phase design-review with no --model records as today and stamps nothing" "AC8: spend --phase design-review --model --effort stamps the review file with both and records the model" "AC8: a review is recorded once: a second spend naming the same file is refused, whether the model differs or not" "AC8: a refute note records as today in a marked item and stamps nothing, and a typed --model on it is the row's model" "AC8: the author's answering span after --begin records as today in a marked item" "AC8: a grok- model with no typed --effort is refused in a marked item, whatever CLAUDE_EFFORT says" "AC8: a non-claude model takes no effort from CLAUDE_EFFORT" "AC8: the effort is CLAUDE_EFFORT when --effort is not typed, and the line is left out when there is neither" "AC8: a typed --model wins over the session's measured model, which a spend with none records" && \
	fixtureSpec done "AC8: commit --phase code-review in an unmarked raft commits an unstamped review with no --model, as today" "AC8: commit --phase code-review refuses a new review file without --model, committing nothing" "AC8: commit --phase code-review --model stamps every unstamped review file it commits, and leaves a stamped one alone" "AC8: commit takes the effort from CLAUDE_EFFORT when none is typed, and leaves Effort: out when there is neither" "AC8: commit with another phase refuses an unstamped review file in a marked raft, naming --phase code-review, and commits nothing" "AC8: commit --model stamps a modified review file that has no Model: line" "AC8: commit refuses a grok- review with no typed --effort in a marked raft, whatever CLAUDE_EFFORT says, and takes no effort from it for a non-claude model"
}
check "AC8: \`./zn spend --phase design-review --note design-review-NNN --model <id>\` stamps that file with the model and the effort (\`--effort\`, else \`CLAUDE_EFFORT\` for a \`claude-\` id) and in a marked item is refused without \`--model\`, or for a \`grok-\` id without \`--effort\`, while a refute note or no note records as today and stamps nothing; a typed \`--model\` wins over the session's measured model; \`./zn commit --phase code-review --model <id>\` stamps every unstamped review file it commits, and in a marked item committing one without \`--model\`, for a \`grok-\` id without \`--effort\`, or with another phase, is refused; in an unmarked item both behave as today without \`--model\`; \`ledger.isModel\` accepts \`claude-opus-5-5[1m]\`." ac8
ac9() {
	fixtureSpec docs --run "AC9: each of the five skills states the four review kinds" "AC9: each states the stamped record and the --model and --effort record lines" "AC9: each states the three refusals and the mark that scopes them" "AC9: zz-rules lists the mark among the Items front matter and zz-review says the reviewer never writes the record" "AC9: no skill, z-nile's or a project's, says \`on Opus 5.5\`"
}
check "AC9: zz-review, z-design, z-raft, zz-execute and zz-rules state the review kinds, the stamped record, the \`--model\` and \`--effort\` record lines and the three refusals, and no skill says \`on Opus 5.5\`." ac9
check "AC10: the fast specs this change touches still pass, those of them not in \`tests/slow.tsv\` when it runs (the slow tier is the gate's)." runFast
check "AC11: each spec on the Overrides line, and \`tests/tooling/watch-map.spec.luau\`, gives every review it writes by hand the record the rule needs (a \`Model: claude-opus-5-5\` line, or \`--model claude-opus-5-5\` on the commit or spend that records it); this fails on each of today's files." ac11

finish
