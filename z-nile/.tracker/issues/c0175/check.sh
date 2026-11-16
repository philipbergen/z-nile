#!/usr/bin/env bash
# Acceptance checks for c0175. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0175 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0175"

# Every spec here is a plain spec over fake CLIs and fixtures under .cache (runner-cli.spec starts fake agy and opencode scripts
# it writes there; fakes.spec runs the shared fakes): none starts a real model CLI. Their cases build on nothing, but each spec
# runs once, and every criterion then checks that each of its own cases passed: the runner writes each passing case's name to the
# --out file, but only when the whole run passes (z-nile/specs.luau), so one red case leaves the record empty and every
# criterion of that spec reports it (lesson zz-test/out-records-only-a-green-run): read the run's FAIL lines.
OUT="$PWD/.cache/c0175-check"
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

# the fast specs this change touches: of the listed specs, those not in the measured slow tier
# (tests/slow.tsv). The slow tier is the gate's, run by Implementation step 10 (z-nile/check.sh --slow), never by this check.sh.
fastSpecs() {
	local s
	for s in tests/acceptance/c0117/adapters.spec.luau tests/acceptance/c0117/control-cli.spec.luau tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0117/dispatch-cli.spec.luau tests/acceptance/c0117/docs.spec.luau tests/acceptance/c0117/ledger.spec.luau tests/acceptance/c0117/models.spec.luau tests/acceptance/c0117/trackerstate.spec.luau tests/acceptance/c0117/wrapper.spec.luau tests/tooling/dispatch-guards.spec.luau tests/tooling/openlist.spec.luau tests/tooling/raftcheck.spec.luau tests/tooling/repo-fence.spec.luau tests/tooling/trace-skeleton.spec.luau tests/tooling/wrapper-guards.spec.luau tests/tooling/kimi-adapter.spec.luau tests/tooling/kimi-session.spec.luau tests/tooling/roles.spec.luau tests/tooling/work.spec.luau tests/tooling/idea.spec.luau tests/tooling/dispatch-texts.spec.luau; do
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

ac1() {
	fixtureSpec models-cli --run "AC1: models.CLIS lists agy and opencode, each with its one local runtime" "AC1: parse accepts agy's gemini-, claude- and gpt- ids and opencode's opencode-<provider>-<model> ids" "AC1: parse refuses another CLI's model or runtime on agy and opencode, naming the file and the key" "AC1: an opencode id with an escaped / : or @ in its model parses, so every model opencode reaches can be named"
}
check "AC1: \`agy\` and \`opencode\` are supported CLIs: \`models.CLIS\` lists them with the runtimes \`agy-cli\` and \`opencode-cli\`, a \`.models.toml\` role, fallback or member on them parses with agy's \`gemini-\`, \`claude-\` and \`gpt-\` ids and opencode's \`opencode-<provider>-<model>\` ids (a model name's \`/\`, \`:\` and \`@\` written as escapes, so every model opencode reaches can be named), and another CLI's model or runtime is refused when the file loads, naming the file and the key." ac1
ac2() {
	fixtureSpec models-cli "AC2: effortFor lowers agy's effort to the highest the model offers: Opus tops out at high" "AC2: effortFor gives a model that offers none no effort, and leaves other CLIs and unknown models alone" "AC2: a try on agy carries the lowered effort, so the spend row's model id records what ran" "AC2: an agy role of its own is lowered the same way"
}
check "AC2: \`models.effortFor\` lowers an agy try's effort to the highest the model offers (Opus tops out at \`high\`, a model with none takes none) and leaves every other CLI's effort alone, and the tries built for a role, fallback or member on agy carry it, so \`models.id\` records the effort that ran." ac2
ac3() {
	fixtureSpec agy-adapter --run "AC3: the adapter is agy's local runtime, not call-capped, and starts agy headless with its permission-skipping flag" "AC3: no effort on the stage means no --effort flag, and the model is passed as the bare id" "AC3: it counts input + output of each finished step once, with cache reads left out, and the result's total as the final" "AC3: thinking tokens are inside output, never added twice" "AC3: a tool step is running from ACTIVE to DONE, with its name and command on the note, and the session is the conversation" "AC3: a stream with no usage is ok and unmeasured, and a line that is not JSON is the CLI's own text" "AC3: an error result fails the step with the CLI's words, whether the model or the effort was refused" "AC3: an error result that says quota is a quota failure, not a failed step" "AC3: a subagent step is running like a tool, and the stream carries no usage for it: the count is the parent's steps"
}
check "AC3: The \`agy-cli\` adapter starts \`agy -p <prompt> --output-format stream-json --model <bare id> --dangerously-skip-permissions [--effort <e>]\`, counts the input and output of each finished step once (cache reads out, thinking not added twice) with the result's total as the final, tracks a tool step from ACTIVE to DONE, takes the conversation as the session, and ends an error result as failed, or as quota when it says so." ac3
ac4() {
	fixtureSpec opencode-adapter --run "AC4: opencodeModel turns the ledger id into opencode's provider/model" "AC4: every id the ledger takes: opencode ids are plain ledger ids, and none is another CLI's id" "AC4: the adapter is opencode's local runtime and starts opencode headless, json, auto-approving, in the work directory" "AC4: no effort on the stage means no --variant" "AC4: every name opencode reaches is written in the ledger's alphabet and read back: / : @ _ and any other byte" "AC4: the step's environment turns opencode's snapshots and title call off, and leaves the other CLIs' as they were"
}
check "AC4: \`adapters.opencodeModel\` turns the ledger id \`opencode-<provider>-<model>\` into opencode's \`<provider>/<model>\` (a \`_\` in a provider is a hyphen; \`_s\`, \`_c\`, \`_a\`, \`__\` and \`_xHH\` in a model are \`/\`, \`:\`, \`@\`, \`_\` and any other byte, written by \`adapters.opencodeId\`), the \`opencode-cli\` adapter starts \`opencode run <prompt> -m <provider>/<model> --format json --auto --dir <cwd> --print-logs --log-level INFO [--variant <e>]\`, and its step environment turns opencode's snapshots and title call off." ac4
ac5() {
	fixtureSpec opencode-adapter "AC5: it counts input + cache writes + output + reasoning of each finished step once, with cache reads left out" "AC5: the session is the sessionID, and a step that printed no count is ok and unmeasured" "AC5: a tool is running from its permission check on stderr until the step finishes, because stdout shows it only once done" "AC5: an error event fails the step with the CLI's message" "AC5: an error that says rate limit or too many requests is a quota failure, and a step that spent first keeps its count" "AC5: tools run in parallel: the first to finish does not hide a long sibling, and the step's end ends them all" "AC5: isLog tells opencode's log lines from the CLI's own text, and only a log line is a permission check" "AC5: a log line that quotes a quota word in a command is not a wait; the CLI's own stream error is" "AC5: a created line with a parentID names a child session (a subagent); one without does not" "AC5: an error whose message has no quota word but whose body or status says 429 is quota"
}
check "AC5: The \`opencode-cli\` adapter counts the input, cache writes, output and reasoning of each finished step once (cache reads out), takes the sessionID as the session, counts the tools its stderr log shows started and its stdout shows finished (parallel calls included), names the child sessions its log shows, keeps its log lines apart from the CLI's own text, takes its ERROR stream error with a quota word as a wait for quota, and ends an error event as failed, or as quota when it says so (a 429 status or body included)." ac5
ac6() {
	fixtureSpec runner-cli --run "AC6: an agy step's tokens are recorded from its stream, and the session is its conversation" "AC6: an agy error that says quota ends the step as quota, with the CLI's words" "AC6: an opencode step's tokens are recorded, with cache reads left out, and the session is its sessionID" "AC6: an opencode tool that shows only on stderr gets the tool limit: quiet past the stall limit, it is not stalled" "AC6: the same quiet with no tool on stderr is a stall" "AC6: an opencode step past max_tokens is killed as cap, on the running count" "AC6: parallel tools: the first to finish does not hide a long sibling, so a quiet gate is not a stall" "AC6: a command the model runs, quoted in opencode's log, is not the CLI's quota: the step still fails as failed" "AC6: words of waiting in a quoted command, then silence, are a stall, not a wait for quota" "AC6: opencode's own stream error with a quota word, then silence past the stall limit, is a wait for quota" "AC6: a CLI's own non-log error text with quota words and a failing exit is quota" "AC6: a kimi step that hits its monthly limit ends as quota (kimi's real error text, recorded 2026-11-15)"
}
check "AC6: The runner records the tokens of an agy and an opencode step, ends a quota error as quota, gives an opencode tool that shows only on stderr the tool limit instead of the stall limit (a parallel batch included), stalls a quiet step with none, kills a step past \`max_tokens\`, keeps a command quoted in opencode's log from being taken for quota or a wait, ends opencode's own stream error followed by silence as quota, and ends kimi's monthly-limit error as quota." ac6
ac7() {
	fixtureSpec runner-cli "AC7: a stream with a session and no count is read back from opencode's own store: export gives the session's tokens" "AC7: the store is not asked when the stream already carried a count" "AC7: a store that cannot be read leaves the step ok and unmeasured" "AC7: the reader of an export text: the heading is skipped, the tokens become one step_finish line, and anything else gives none" "AC7: only kimi and opencode keep a reader: agy's conversations are protobuf, so its steps stay unmeasured" "AC7: subagents' tokens are read after the step, once per child session, and the live cap is the parent's only" "AC7: an id that is not an opencode session id never reaches the CLI: the CLI is not started at all"
}
check "AC7: A stream that carried no count is read back from the CLI's own session store: \`opencode export <session>\` supplies an opencode step's tokens, it is not asked when the stream carried a count, an unreadable store leaves the step ok and unmeasured, agy keeps no reader, an id that is not a session id never starts the CLI, and the child sessions (subagents) opencode's log named are read after the step, once each, with the live cap seeing the parent only and the detail saying so." ac7
ac8() {
	fixtureSpec root-models --run "AC8: Opus through agy passes the review kinds at any effort, as Opus through claude does; the other agy models do not" "AC8: no opencode id passes a review kind, at any effort, xai's Grok at xhigh included" "AC8: no review role of the root file has an opencode try, and no review model the file can pick is refused for its kind"
}
check "AC8: The review kinds are unchanged by the new CLIs: Opus through agy passes at any effort, no other agy model passes, no opencode id passes at any effort (xai's Grok at \`xhigh\` included), and no review role of the root \`.models.toml\` has an opencode try." ac8
ac9() {
	fixtureSpec root-models "AC9: every model line a CLI reaches is in [families]: agy's Gemini, Claude and GPT-OSS ids, each opencode provider its own" "AC9: an opencode model is never in the model line of the same model reached another way" "AC9: every model any role, fallback or member of the file names has a model line, so no rotating role fails to resolve"
}
check "AC9: Every model any CLI of the root \`.models.toml\` reaches has a model line in \`[families]\`: \`gemini\` and \`gpt\` for agy's, and one line per opencode provider, none the line of the same model reached another way." ac9
ac10() {
	fixtureSpec root-models "AC10: agy ends every role's CLIs and opencode ends the authoring roles' and the stream review's, in the file's order" "AC10: each try is recorded as the model and effort that ran: agy's Opus at high where the stage asks xhigh" "AC10: the new tries carry their role's rank and cap, and no cap of their own" "AC10: the author record matches Opus through agy to Opus through claude, and each new id to its own model"
}
check "AC10: The root \`.models.toml\` puts agy last among every role's CLIs and opencode last among the idea, design and implementation roles' and the stream review's, with Gemini flash and DeepSeek flash as the stream review's cheap members, and each try is recorded as the model and effort that ran." ac10
ac11() {
	fixtureSpec docs --run "AC11: zz-rules lists the six CLIs and their six runtimes" "AC11: zz-rules states each new CLI's headless route, with its permission-skipping flag" "AC11: zz-rules says where each CLI's token count comes from, and that a stream with none is read from the CLI's store" "AC11: zz-rules states the ids: agy's bare names and lowered effort, opencode's opencode-<provider>-<model> and its model lines" "AC11: zz-review says who may review through agy, kimi and opencode" "AC11: zz-test and z-work name the new CLIs where they name the others" "AC11: the README says the three exist and lists the six CLIs of .models.toml" "AC11: the root .models.toml's comments explain the new CLIs" "AC11: zz-rules states opencode's run: subagent tokens read after the step, the cap, the retry wait, the log lines, the project file" "AC11: z-work says what agy's and opencode's rows record, and the README worker line names opencode, not deepseek"
}
check "AC11: The documents that list the CLIs (zz-rules, zz-review, zz-test, z-work, the README and the root \`.models.toml\`) name all six with their six runtimes and state the routes, the token sources, the ids, agy's effort, opencode's run and who may review through each, and z-work and the README worker line say what agy's and opencode's rows record and name \`opencode\`, not \`deepseek\`." ac11
ac12() {
	fixtureSpec fakes --run "AC12: the fake agy prints a stream its adapter counts: input + output of the step, cache reads out" "AC12: the fake opencode prints a step_finish its adapter counts, and names its session" "AC12: the fake kimi names its session and prints no usage: ok and unmeasured, as the real one is before its wire is read" "AC12: each fake's quota mode ends in a quota failure" "AC12: the fake that fails prints no usage and fails, for each of them" "AC12: the cap mode of each fake prints lines its adapter counts at 1001 each" "AC12: the harness writes an executable fake for each of the six CLIs, and a gh and a git"
}
check "AC12: The shared fake CLIs fake \`kimi\`, \`agy\` and \`opencode\` too: each fake's stream is counted by its adapter, its quota and fail modes end as quota and failed, and the harness writes all six." ac12
ac13() {
	fixtureSpec cliguard --run "AC13: seal makes an existing project file read-only, in a repository and in a linked worktree's common directory" "AC13: seal does nothing without the file, outside a repository, or for another runtime" "AC13: a step that tries to rewrite the project file leaves it as it was, and the step still runs" "AC13: a step that creates the file where there was none finds it read-only afterwards"
}
check "AC13: The runner makes an existing \`<common git dir>/opencode\` project file read-only before and after an opencode step, in a repository and in a linked worktree, so no step rewrites it, and a file a step creates is read-only afterwards." ac13
check "AC14: The fast specs this change touches still pass, those of them not in \`tests/slow.tsv\` when it runs (the slow tier is the gate's)." runFast

finish
