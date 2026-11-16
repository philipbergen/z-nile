#!/usr/bin/env bash
# Acceptance checks for c0251. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0251 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0251"

# family, reviewpool, priors, stamp, models, roles and docs are plain specs. priors, board-fallback and the dispatch specs write
# fixtures under .cache: dispatch-pool drives `./zn dispatch zz-review` and `./zn idea` against fake CLIs (the model-aware claude
# and a kimi, as c0306's dispatch-review spec does), interactive drives the dry-run, `./zn spend` and `./zn commit` in offline
# fixtures. Their cases build on each other, so each spec runs once, and every criterion then checks that each of its own cases
# passed: the runner writes each passing case's name to the --out file, but only when the whole run passes (z-nile/specs.luau),
# so one red case leaves the record empty and every criterion of that spec reports it (lesson
# zz-test/out-records-only-a-green-run): read the run's FAIL lines.
OUT="$PWD/.cache/c0251-check"
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

ac1() {
	fixtureSpec family --run "AC1: family.of returns the family of the longest matching prefix, whatever the table order" "AC1: family.of gives nil when no prefix matches, and tolerates a context marker like [1m]" "AC1: family.same is false when either side is nil, and true for one family"
}
check "AC1: \`family.of\` returns the family of the longest matching prefix of the bare model id, nil when none matches, and \`same\` is false when either side is nil." ac1
ac2() {
	fixtureSpec family "AC2: models.parse reads [families] into the layer" "AC2: a closer file replaces only the family keys it sets" "AC2: a prefix under two families, a non-list, an empty prefix and an empty list are refused" "AC2: rotate takes only a boolean on a role" "AC2: roleFor gives stream-review for a stream review, and the other modes keep their roles" "AC2: a rotate role whose model has no family fails at resolve, naming the role and the model"
}
check "AC2: \`.models.toml\` parses \`[families]\` (a closer file replaces only the keys it sets; a prefix under two families is refused) and \`rotate\`; \`roleFor(\"zz-review\",\"stream\")\` is \`stream-review\`; a \`rotate\` role whose model has no family fails at resolve." ac2
ac3() {
	local rc=0
	fixtureSpec reviewpool --run "AC3: an Opus author sends the review to the other lines first and keeps Opus last, the exact model after" "AC3: the author's exact model goes after the other models of its line" "AC3: the previous round's line goes to tier 2, after tier 1 and before the author's own" "AC3: tier 1 needs both a different line from the author and from the previous round" "AC3: the order inside a tier is the role's order, not the model ids' order" "AC3: no try is ever dropped, so the list is empty only when the tries are" "AC3: a context marker on the author's id changes nothing" "AC3: an unknown family is never tier 1 against a known author" "AC3: an unknown author gives every try tier 1 and no reason, and the order is the role's" || rc=1
	fixtureSpec dispatch-pool --run "AC3: a final review's author is the writers of the build only, not the idea's and the design's" || rc=1
	return $rc
}
check "AC3: \`reviewpool.order\` is a stable partition into tier 1 (differs from the author and the previous round), tier 2 (differs from the author), tier 3 (the author's family, its exact model last), never drops a try, and treats an unknown family as not different." ac3
ac4() {
	fixtureSpec priors --run "AC4: the highest lifecycle rank decides, not the file number" "AC4: only the ranks up to the kind being written count" "AC4: inside one rank the highest round number decides" "AC4: a refused round counts (an off-model record), and so does a flagged one" "AC4: unstamped files are skipped and the next stamped one is the previous round" "AC4: ties across a raft's member folders all count, each model once, with a bare id" "AC4: an unmarked item has no previous reviewer" "AC4: a stream review reads none (rank 0 admits no file), and the pure ranking agrees with the reader"
}
check "AC4: previous reviewers are the stamped reviews of the highest lifecycle rank up to the kind being written, a refused or flagged round counts, unstamped files are skipped, and a stream review and an unmarked item have none." ac4
ac5() {
	fixtureSpec dispatch-pool "AC5: without the Fable member an Opus-written design goes to kimi first, and claude is never started" "AC5: a Sonnet-written code review goes to Opus first, unflagged" "AC5: a quota on the first falls to the next pick, and AC17: even to the other model of the same CLI" "AC5: a role whose only try is the author's exact model still runs it, flagged" "AC5: c0306's refused tries are still skipped on the picked order: grok at effort high is never started"
}
check "AC5: a dispatched review runs the first runnable pick (an Opus-written design goes to kimi or grok first, a Sonnet-written code review to Opus), falls to the next on quota, skips c0306's refused tries, and runs the author's exact model when it is the only one left." ac5
ac6() {
	local rc=0
	fixtureSpec stamp --run "AC6: stamp prepends Fallback: after Model: and Effort:, in the same call" "AC6: a stamped review reads back its model, effort and fallback, and a file that records a model is never stamped again" "AC6: a reason that is not one short line is refused" "AC6: fallbackOf reads the line within 12 lines, beside Commit: and Patch:" "AC6: only a tier 3 pick has a reason, and it names the exact model" "AC6: a same-line model that is not the exact one names the line" "AC6: the reason says assumed or unknown when the author is not recorded, and stays one short line" || rc=1
	fixtureSpec dispatch-pool "AC17: with Fable refused kimi runs next, and AC6: the fall-through to a tier 1 pick stamps no Fallback:" "AC17: with every other line refused, Opus runs last and the file carries Fallback: with the exact-model reason, and AC6: only the attempt that wrote it counts" "AC6: Fallback: is stamped in the same call as Model:, naming an assumed author when no row records it" || rc=1
	return $rc
}
check "AC6: the dispatcher stamps \`Fallback: <reason>\` in the same call as \`Model:\`, only when the attempt that wrote the review was tier 3, and \`reviewmodel.fallbackOf\` reads it within 12 lines beside \`Commit:\`/\`Patch:\`." ac6
ac7() {
	fixtureSpec dispatch-pool "AC7: in a marked item the next round is allowed over a newest round that carries Fallback:" "AC7: the round it filed counts as a prior for the next, and an unflagged newest round allows none"
}
check "AC7: in a marked item the next round is allowed over a newest round that carries \`Fallback:\`, takes the next number, and counts as a prior." ac7
ac8() {
	fixtureSpec board-fallback --run "AC8: boardview.fallbacks lists the newest round of each kind that carries Fallback:, per folder" "AC8: two folders are judged apart, so a clean newest round in one does not hide a flagged one in the other" "AC8: a raft carries fallbackReviews for its own and its members' newest flagged rounds only" "AC8: an issue carries fallbackReviews for its own newest flagged round, in a raft or not" "AC8: the flag clears when a later round has no Fallback: line" "AC8: the page names the flag and the command that asks for the cross-model re-review"
}
check "AC8: the board flags a raft or issue whose newest round of a kind carries \`Fallback:\` and clears the flag when a later round has none." ac8
ac9() {
	fixtureSpec interactive --run "AC9: --dry-run prints the pool line, each try's tier, family and fallback, and the pick" "AC9: --author is the live author: it replaces the recorded one and the order follows it" "AC9: the printed order equals the order the run tries" "AC9: --author does not leak into the run's own plan: a run without it uses the recorded author"
}
check "AC9: \`./zn dispatch zz-review <id> --mode <m> --dry-run [--author <id>]\` prints the pool line, per-try tier, family and fallback, and a \`pick:\` line, in the order the run would try." ac9
ac10() {
	fixtureSpec interactive "AC10: spend --phase design-review --model stamps Fallback: when the typed model is the writer's line" "AC10: it stamps none when the typed model is the pick, and the lead types no reason" "AC10: it stamps Fallback: when the pick was not a claude- id and a different model was typed" "AC10: a typed id whose plan cannot be built, or whose role does not rotate, stamps no Fallback:" "AC10: commit --phase code-review --model stamps Fallback: when the typed model is the layer writer's line" "AC10: a non-Claude pick that was not the model that ran is flagged on a commit too" "AC10: pool.interactiveReason is the pure rule: the writer's line, or a non-Claude pick that was not the model that ran"
}
check "AC10: an interactive \`spend --phase design-review --model\` or \`commit --phase code-review --model\` stamps \`Fallback:\` when the typed model is the author's family, or when the pick was not a \`claude-\` id and a different model was typed, and stamps none otherwise." ac10
ac11() {
	fixtureSpec dispatch-pool "AC11: a stream review runs on stream-review, picks away from the author's family and reads no priors" "AC11: a Haiku-written layer's stream review goes to the next line, kimi, first"
}
check "AC11: a stream review runs on \`stream-review\`, picks away from the author's family and reads no priors." ac11
ac12() {
	fixtureSpec dispatch-pool "AC12: the idea challenge orders through the same picker with the draft's real writer as the author, and its review stays unstamped"
}
check "AC12: the idea challenge orders through the same picker with the real writer as the author and its review stays unstamped." ac12
ac13() {
	local rc=0
	fixtureSpec docs --run "AC13: zz-review states the tier rule, the interactive pick and the Fallback: line" "AC13: z-design, z-raft, zz-execute and zz-rules restate who reviews" "AC13: the review-model rule and the visible record keep their text, and zz-review's record names the flag" "AC13: the README says the pool exists and its c0251 markers read exists" "AC13: .models.toml's header comment states the pool, the tiers and the picker" "AC13: AGENTS.md carries none of the new rule text (it is c0332's)" || rc=1
	[[ -z "$(git -C "$ZN_ROOT" diff --name-only "$(git -C "$ZN_ROOT" merge-base origin/main HEAD)" -- AGENTS.md)" ]] || { echo "AGENTS.md changed: it is c0332's"; rc=1; }
	return $rc
}
check "AC13: the skills, \`.models.toml\` comments and README state the tier rule, the README markers read \`*exists*\`, and AGENTS.md is unchanged." ac13
ac14() {
	fixtureSpec dispatch-pool "AC14: a role with no rotate tries in the toml order, whoever wrote the text" "AC14: a fixture with no [families] and no rotate loads and tries in the toml order"
}
check "AC14: a role with no \`rotate\` and a fixture with no \`[families]\` try in the toml order exactly as before." ac14
ac16() {
	fixtureSpec models --run "AC16: [member.*] and a role's pool parse" "AC16: the tries are the primary, the members in the order listed, then the fallbacks" "AC16: two specs on claude coexist, each with its own model, and a member carries the role's rank, cap and effort" "AC16: order and specs keep the per-CLI view: each CLI once, its first spec" "AC16: Resolved.pool is the tries in order, and models.tries returns it" "AC16: a member that is a CLI name, a name with no member, a name listed twice and a repeated cli and model are refused" "AC16: a member with the wrong runtime, a model of another CLI, no cli or a role-only key is refused" "AC16: a closer file replaces only the member keys it sets" "AC16: forRaft keys each try by cli and model, taking the strongest of the members' same-keyed entries" "AC16: knownModels includes the members' models, bare and sorted"
}
check "AC16: a role may name \`pool\` members (\`[member.<name>]\` with cli, model, runtime) beside \`fallbacks\`; its tries are primary, members, fallbacks, two on one CLI coexist, \`Resolved.order\` and \`.specs\` keep the per-CLI view, and each malformed member is refused." ac16
ac17() {
	fixtureSpec dispatch-pool "AC17: an Opus-written design picks Fable first, on the claude fake, and the file records it with no Fallback:" "AC5: a quota on the first falls to the next pick, and AC17: even to the other model of the same CLI" "AC17: with Fable refused kimi runs next, and AC6: the fall-through to a tier 1 pick stamps no Fallback:" "AC17: with every other line refused, Opus runs last and the file carries Fallback: with the exact-model reason, and AC6: only the attempt that wrote it counts"
}
check "AC17: an Opus-written design is reviewed first by Fable (unflagged), then kimi, grok, and Opus last with \`Fallback:\`; a quota on one model falls to the next try even on the same CLI." ac17
ac18() {
	fixtureSpec docs "AC18: the root .models.toml names the members, the pools and rotate on the review roles" "AC18: the pools in the order the tries run them: primary, the pool member, then the CLI fallbacks" "AC18: stream-review is claude-haiku-5-5 with the fallbacks kimi and grok, and the cheap role runs a stream review"
}
check "AC18: the root \`.models.toml\` names Fable in the design-challenge, raft and code-review pools, Opus in final-review's, and \`stream-review\` on \`claude-haiku-5-5\` with fallbacks \`kimi\` and \`grok\`." ac18
ac15() {
	fixtureSpec roles --run "AC15: tries are the role, then its fallbacks, and the author's model stays in the list" "AC15: the author's model is not dropped by its recorded id, with or without an effort" "AC15: it does not stop when the only model left is the author's" "AC15: a role with no CLI that has a spec still fails, naming the role"
}
check "AC15: \`models.tries\` keeps the author's model and no longer stops." ac15

finish
