#!/usr/bin/env bash
# Acceptance checks for c0251. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0251 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0251"

# family, reviewpool, stamp, designedby, frontier, models, roles and docs are plain specs. priors, floor and the dispatch specs write
# fixtures under .cache: dispatch-pool drives `./zn dispatch zz-review` and `./zn idea` against fake CLIs (the model-aware claude
# and a kimi, as c0306's dispatch-review spec does), interactive drives the dry-run, `./zn spend` and `./zn commit` in offline
# fixtures, floor drives `./zn done` in two offline rafts. Their cases build on each other, so each spec runs once, and every criterion then checks that each of its own cases
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
	fixtureSpec family "AC2: models.parse reads [families] into the layer" "AC2: a closer file replaces only the family keys it sets" "AC2: a prefix under two families, a non-list, an empty prefix and an empty list are refused" "AC2: rotate takes only a boolean on a role" "AC2: roleFor gives stream-review for a stream review and raft-review for a raft review, and the other modes keep their roles" "AC2: a rotate role whose model has no family fails at resolve, naming the role and the model"
}
check "AC2: \`.models.toml\` parses \`[families]\` (a closer file replaces only the keys it sets; a prefix under two families is refused) and \`rotate\`; \`roleFor(\"zz-review\",\"stream\")\` is \`stream-review\` and \`roleFor(\"zz-review\",\"raft\")\` is \`raft-review\`; a \`rotate\` role whose model has no family fails at resolve." ac2
ac3() {
	local rc=0
	fixtureSpec reviewpool --run "AC3: an Opus author sends the review to the other lines first and keeps Opus last, the exact model after" "AC3: the author's exact model goes after the other models of its line" "AC3: the previous round's line goes to tier 2, after tier 1 and before the author's own" "AC3: tier 1 needs both a different line from the author and from the previous round" "AC3: the order inside a tier is the role's order, not the model ids' order" "AC3: no try is ever dropped, so the list is empty only when the tries are" "AC3: a context marker on the author's id changes nothing" "AC3: an unknown family is never tier 1 against a known author" "AC3: an unknown author gives every try tier 1 and no reason, and the order is the role's" || rc=1
	fixtureSpec dispatch-pool --run "AC3: a final review's author is the writers of the build only, not the idea's and the design's" || rc=1
	return $rc
}
check "AC3: \`reviewpool.order\` is a stable partition into tier 1 (differs from the author and the previous round), tier 2 (differs from the author), tier 3 (the author's family, its exact model last), never drops a try, and treats an unknown family as not different." ac3
ac4() {
	local rc=0
	fixtureSpec dispatch-pool "AC4: an unmarked item's stamped round is a previous reviewer" || rc=1
	fixtureSpec priors --run "AC4: the highest lifecycle rank decides, not the file number" "AC4: only the ranks up to the kind being written count" "AC4: inside one rank the highest round number decides" "AC4: a round on any model counts, a cheap one included, and so does one that records a Fallback:" "AC4: unstamped files are skipped and the next stamped one is the previous round" "AC4: ties across a raft's member folders all count, each model once, with a bare id" "AC4: inside one folder only the newest round at the top rank counts, and each folder contributes its own" "AC4: an unmarked item's stamped rounds count too: c0306 stamps every review it files" "AC4: a stream review reads none (rank 0 admits no file), and the pure ranking agrees with the reader" || rc=1
	return $rc
}
check "AC4: previous reviewers are the stamped reviews of the highest lifecycle rank up to the kind being written, a round on any model counts (one that records a \`Fallback:\` too), unstamped files are skipped, each folder's newest round at that rank counts (round numbers are never compared between folders), unmarked items count too, and a stream review has none." ac4
ac5() {
	fixtureSpec dispatch-pool "AC5: without the Fable member an Opus-designed document goes to kimi first, and claude is never started" "AC5: a Sonnet-written code review goes to Opus first, unflagged" "AC5: a quota on the first falls to the next pick, and AC17: even to the other model of the same CLI" "AC5: a role whose only try is the author's exact model still runs it, with a Fallback: line" "AC5: any model may run any review: grok-4.7 at effort high is started when the Claude models and kimi fail, and its review is filed"
}
check "AC5: a dispatched review runs the first runnable pick (an Opus-designed document goes to kimi or grok first, a Sonnet-written code review to Opus), falls to the next on quota, runs on any model (a grok at effort high is not skipped), and runs the author's exact model when it is the only one left." ac5
ac6() {
	local rc=0
	fixtureSpec dispatch-pool "AC17: with Fable out of quota kimi runs next, and AC6: the fall-through to a tier 1 pick stamps no Fallback:" "AC17: with every other line failing, Opus runs last and the file carries Fallback: with the exact-model reason, and AC6: only the attempt that wrote it counts" || rc=1
	fixtureSpec stamp --run "AC6: stamp prepends Fallback: after Model: and Effort:, in the same call" "AC6: a stamped review reads back its model, effort and fallback, and a file that records a model is never stamped again" "AC6: a reason that is not one short line is refused" "AC6: fallbackOf reads the line within 12 lines, beside Commit: and Patch:" "AC6: only a tier 3 pick has a reason, and it names the exact model" "AC6: a same-line model that is not the exact one names the line" "AC6: the reason never says the author was assumed, and stays one short line" || rc=1
	return $rc
}
check "AC6: the dispatcher stamps \`Fallback: <reason>\` in the same call as \`Model:\`, only when the attempt that wrote the review was tier 3, the reason never says the author was assumed, and \`reviewmodel.fallbackOf\` reads it within 12 lines beside \`Commit:\`/\`Patch:\`." ac6
ac7() {
	fixtureSpec dispatch-pool "AC7: a round that carries Fallback: allows no second round, in a marked item or not (no re-review)"
}
check "AC7: a second review of a kind is refused in any item, marked or not, whether or not the newest round records a \`Fallback:\` (no board flag, no cross-model re-review); the only second round is the extra round of the frontier floor (AC21)." ac7
ac8() {
	local rc=0
	fixtureSpec dispatch-pool "AC8: a design review of a document with no designed-by line is refused, naming the document, whatever the spend rows say, and no CLI starts" "AC8: the writer of a design is its designed-by line, not the spend rows, and a list names every model that wrote it" "AC8: under dispatch the tool writes the line from the attempt's own model, and adds a second model that revises" || rc=1
	fixtureSpec designedby --run "AC8: of reads one id, a list, and nothing for a missing or empty line" "AC8: of reads a bare id (a context marker cut) once each, and only the front matter, never the body" "AC8: add writes the line when there is none, in the front matter only, and leaves the body alone" "AC8: add keeps the same model once, and a second model that revises makes it a list" "AC8: add gives nil for a document with no front matter, and the refusal names the item, the document and the line" || rc=1
	return $rc
}
check "AC8: the writer of a design or raft is the \`designed-by\` line of its document (one id or a list; the body is never read, a second model that revises is added once); the tool writes it under dispatch from the authoring attempt's model; a design review or raft review of a document with no line is refused (dispatched, \`--dry-run\` and the interactive \`spend\` stamp), whatever the spend rows say; there is no \`--author\` flag." ac8
ac9() {
	fixtureSpec interactive --run "AC9: --dry-run prints the pool line, each try's tier, family and fallback, and the pick" "AC9: the lead's own model is no input: a typed --author changes nothing, and the line decides" "AC9: the printed order equals the order the run tries" "AC9: the run uses the designed-by line too: c0031's run starts Opus first"
}
check "AC9: \`./zn dispatch zz-review <id> --mode <m> --dry-run\` prints the pool line (author, how recorded, previous), per-try tier, family and fallback, and a \`pick:\` line, in the order the run would try; a typed \`--author\` changes nothing." ac9
ac10() {
	fixtureSpec interactive "AC10: a spend stamps Fallback: when the typed model is the writer's line, the writer read from the designed-by line" "AC10: the designed-by line beats the spend rows, and a list names every writer" "AC10: a spend of a design review on a document with no designed-by line is refused, stamps nothing and names the document" "AC10: ZN_MODEL is not the writer of a design: the line is" "AC10: it stamps Fallback: when the pick was not a claude- id and a different model was typed" "AC10: a typed id whose role does not rotate stamps no Fallback:" "AC10: a spend on a raft's folder is a raft-mode review, read against the raft document's designed-by line" "AC10: the same raft reviewed by the writer's own line is flagged" "AC10: commit --phase code-review --model stamps Fallback: when the typed model is the layer writer's line" "AC10: commit takes no --author: the layer's writer is the build row, whatever the lead types" "AC10: a final review file is read in final mode, whose role is final-review" "AC10: a non-Claude pick that was not the model that ran is flagged on a commit too" "AC10: pool.interactiveReason is the pure rule: the writer's line, or a non-Claude pick that was not the model that ran"
}
check "AC10: an interactive \`spend --phase design-review --model\` or \`commit --phase code-review --model\` stamps \`Fallback:\`, against the document's \`designed-by\` line (design, raft) or the build rows (code, final), when the typed model is the author's family, or when the pick was not a \`claude-\` id and a different model was typed, and stamps none otherwise; \`ZN_MODEL\` is no author." ac10
ac11() {
	fixtureSpec dispatch-pool "AC11: a stream review runs on stream-review, picks away from the author's family and reads no priors" "AC11: a Haiku-written layer's stream review goes to the cheap Sonnet first, unflagged" "AC11: the stream list is Haiku, Sonnet, grok-4.6, then composer: with the first three failing composer runs" "AC11: a stream review run by the layer writer's own line records Fallback:, and allows no second round"
}
check "AC11: a stream review runs on \`stream-review\` (the list Haiku, Sonnet, grok-4.6, composer, in that order, from \`.models.toml\`), picks away from the author's family, reads no priors, records \`Fallback:\` when the layer's own line ran it, and allows no second round." ac11
ac12() {
	fixtureSpec dispatch-pool "AC12: the idea challenge orders through the same picker with the draft's real writer as the author, and its review records the model and the fallback"
}
check "AC12: the idea challenge orders through the same picker with the real writer as the author, and its review records the model and, for a fallback, \`Fallback:\`." ac12
ac13() {
	local rc=0
	fixtureSpec docs --run "AC13: zz-review states the tier rule, the designed-by line, the interactive pick, the Fallback: line and the floor" "AC13: z-design, z-raft, zz-execute and zz-rules restate who reviews" "AC13: the old review-model rule is gone from every skill, and the frontier floor is stated in the five that carried it" "AC13: the README says the pool exists and its c0251 markers read exists" "AC13: .models.toml's header comment states the pool, the tiers and the picker" "AC13: AGENTS.md carries none of the new rule text (it is c0332's)" || rc=1
	[[ -z "$(git -C "$ZN_ROOT" diff --name-only "$(git -C "$ZN_ROOT" merge-base origin/main HEAD)" -- AGENTS.md)" ]] || { echo "AGENTS.md changed: it is c0332's"; rc=1; }
	return $rc
}
check "AC13: the skills, \`.models.toml\` comments and README state the tier rule, the \`designed-by\` line and the frontier floor, no skill still says a review must run on a review model or takes \`--author\`, the README markers read \`*exists*\`, and AGENTS.md is unchanged." ac13
ac14() {
	fixtureSpec dispatch-pool "AC14: a role with no rotate tries in the toml order, whoever wrote the text" "AC14: z-raft writes on the raft role, which has neither a pool nor a rotation; the raft review has both on its own role" "AC14: a raft-mode review rotates on the raft document's designed-by line and on the raft's previous coherence round" "AC14: a fixture with no [families] and no rotate loads and tries in the toml order"
}
check "AC14: a role with no \`rotate\`, a fixture with no \`[families]\` and z-raft's writing step on the \`raft\` role (which has no pool and no rotation, apart from \`raft-review\`) try in the toml order, with no author dropped." ac14
ac16() {
	fixtureSpec models --run "AC16: [member.*] and a role's pool parse" "AC16: the tries are the primary, the members in the order listed, then the fallbacks" "AC16: two specs on claude coexist, each with its own model, and a member carries the role's rank, cap and effort" "AC16: order and specs keep the per-CLI view: each CLI once, its first spec" "AC16: Resolved.pool is the tries in order, and models.tries returns it" "AC16: a member that is a CLI name, a name with no member, a name listed twice and a repeated cli and model are refused" "AC16: a member with the wrong runtime, a model of another CLI, no cli or a role-only key is refused" "AC16: a closer file replaces only the member keys it sets" "AC16: forRaft keys each try by cli and model, taking the strongest of the members' same-keyed entries" "AC16: knownModels includes the members' models, bare and sorted"
}
check "AC16: a role may name \`pool\` members (\`[member.<name>]\` with cli, model, runtime) beside \`fallbacks\`; its tries are primary, members, fallbacks, two on one CLI coexist, \`Resolved.order\` and \`.specs\` keep the per-CLI view, and each malformed member is refused." ac16
ac17() {
	fixtureSpec dispatch-pool "AC17: an Opus-designed document picks Fable first, on the claude fake, and the file records it with no Fallback:" "AC5: a quota on the first falls to the next pick, and AC17: even to the other model of the same CLI" "AC17: with Fable out of quota kimi runs next, and AC6: the fall-through to a tier 1 pick stamps no Fallback:" "AC17: with every other line failing, Opus runs last and the file carries Fallback: with the exact-model reason, and AC6: only the attempt that wrote it counts" "AC17: a code review reads the build rows, and no designed-by line"
}
check "AC17: an Opus-designed document is reviewed first by Fable (recorded without a fallback), then kimi, grok, and Opus last with \`Fallback:\`; a quota on one model falls to the next try even on the same CLI; a code review reads the build rows and no \`designed-by\` line, and with no row the author is unknown and no try is a fallback." ac17
ac18() {
	fixtureSpec docs "AC18: the root .models.toml names the members, the pools, rotate on the review roles and the frontier list" "AC18: the pools in the order the tries run them: primary, the pool member, then the CLI fallbacks" "AC18: the stream-review list is Haiku, Sonnet, grok-4.6, then composer, with no CLI fallback; kimi r2.8 is not seeded"
}
check "AC18: the root \`.models.toml\` names Fable in the design-challenge, raft-review and code-review pools, no pool on final-review (Fable, kimi, grok at xhigh, then Opus last), no pool and no rotation on \`raft\`, the stream-review list (Haiku, Sonnet, grok-4.6, composer) with no CLI fallback, and the frontier list." ac18
ac19() {
	fixtureSpec frontier --run "AC19: listed matches a bare model id, ignores a context marker, and an @effort entry needs that effort" "AC19: check is met by one listed review anywhere, and unmet it names the code, each review found and the list" "AC19: an empty list sets no floor" "AC19: seenIn keeps the code and final reviews only, with their record" "AC19: models.parse reads [review] frontier, a closer file replaces the list whole, and bad entries are refused" "AC19: the root .models.toml seeds the list: Opus, Fable, kimi k3.1 pro, grok 4.7 at xhigh and Gemini 4 Argon"
}
check "AC19: \`frontier.check\` says whether a landing's code and final reviews include one by a model on the \`[review] frontier\` list (a bare id, or \`<id>@<effort>\` for that effort; one review anywhere meets it; design, stream and idea reviews and a review with no record do not count; an empty list sets no floor) and, unmet, names the code \`no-frontier-review\`, each review found and the list; \`[review] frontier\` parses, a closer file replaces it whole, and the root file seeds Opus, Fable, kimi k3.1 pro, grok 4.7 at xhigh and Gemini 4 Argon." ac19
ac20() {
	local rc=0
	fixtureSpec frontier "AC20: any model may run any review: ok refuses no recorded model and problem names only a missing record" "AC20: frontierVerdict reads the code and final reviews of every folder of a landing, one listed review meeting the floor" || rc=1
	fixtureSpec floor --run "AC20: done refuses a landing whose only code review is on a model off the list, naming the code, the file, the model and the extra round" "AC20: a stream review on Fable, a design review on Fable and a grok review at high do not meet the floor" "AC20: a later round on a listed model meets it, the Sonnet round is no refusal, and done lands the raft" "AC20: the floor holds for an unmarked raft too: every landing" "AC20: one frontier review in a member's folder meets it for the whole raft, though the final review is off the list" || rc=1
	return $rc
}
check "AC20: \`./zn done\` refuses a landing with no code or final review of the landed code by a frontier model, in a marked raft and an unmarked one, naming \`no-frontier-review\`, the files and models found and the extra round \`./zn dispatch zz-review <R-id> --mode final --frontier\`; one frontier review in the raft's or a member's folder lands it; and any model may run any review (\`reviewmodel.ok\` refuses no recorded model)." ac20
ac21() {
	fixtureSpec dispatch-pool "AC21: the extra round of the frontier floor runs only a frontier model and is allowed over the newest round when the floor is unmet" "AC21: with the floor met an extra round is refused before any CLI starts, and an ordinary second round still is" "AC21: a frontier round starts no try that is off the frontier list" "AC21: a list entry with @effort needs that effort: grok-4.7 at high leaves the floor unmet, at xhigh meets it" "AC21: when every frontier model is out of quota the run waits: exit 6, a waiting line, and no review is filed"
}
check "AC21: \`./zn dispatch zz-review <id> --mode code|final --frontier\` runs only a try the frontier list names, is refused before any CLI starts when the floor is met, files the next-numbered round over the newest one when it is not, and exits 6 with a waiting line (filing nothing) when every frontier model is out of quota or not installed, while any other failure exits 1." ac21
ac15() {
	fixtureSpec roles --run "AC15: tries are the role, then its fallbacks, and the author's model stays in the list" "AC15: the author's model is not dropped by its recorded id, with or without an effort" "AC15: it does not stop when the only model left is the author's" "AC15: a role with no CLI that has a spec still fails, naming the role"
}
check "AC15: \`models.tries\` keeps the author's model and no longer stops." ac15

finish
