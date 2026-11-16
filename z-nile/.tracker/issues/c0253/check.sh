#!/usr/bin/env bash
# Acceptance checks for c0253. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0253 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0253"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# Each spec file runs once (its cases build on each other: the loop and the command specs share a fixture), and every
# criterion then checks that each of its own cases passed: the runner writes each passing case's name to the --out
# file, but only when the whole run passes (z-nile/specs.luau), so one red case leaves the record empty and every
# criterion of that spec reports it (lesson zz-test/out-records-only-a-green-run): read the run's FAIL lines.
OUT="$PWD/.cache/c0253-check"
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

# AC13: existing specs the change stands on.
runRegression() {
	lune run tests/run -- tests/tooling/work.spec.luau tests/tooling/dispatch-texts.spec.luau tests/acceptance/c0117/models.spec.luau tests/acceptance/c0191/reap.spec.luau tests/acceptance/c0193/tree.spec.luau tests/meta/scanning-loops.spec.luau tests/meta/architecture.spec.luau
}

ac1() {
	fixtureSpec pure --run "AC1: reads the one line next prints as a pick, for each of the four kinds" "AC1: nothing claimable is exit 1 with c0249's own stderr line, and nothing else" "AC1: a pick is run by one dispatcher call, in the documented argument order"
	fixtureSpec session --run "AC1: takes the raft next prints and runs it through the dispatcher's chain with the person's CLI"
}
check "AC1: The supervisor takes exactly what \`./zn next\` prints (\`<id> lost|raft|rafting|draft <why>\`) and runs each pick through the dispatcher's chain, \`./zn dispatch <id> --worker\` (with the person's CLI and, on a host that does not land, \`--no-run\`), never through a launcher of its own; a real \`./zn work --once\` over the fake CLIs readies the raft and runs its z-run step on the person's CLI." ac1
ac2() {
	fixtureSpec dispatch --run "AC2: a raft's z-run session is new at first and resumed on a rerun, on the CLI that ran it"
	fixtureSpec loop --run "AC2: a pick goes to the dispatcher's chain with the person's CLI, and a finished chain is moved" "AC2: a draft, a rafting and a lost pick each go through the chain the same way" "AC2: a raft the previous run held is carried on before next is asked" "AC2: the state file names the item held while its chain runs, and nothing held when it ends"
	fixtureSpec pure "AC2: one CLI session per raft: the same CLI resumes it, another CLI starts a new one that reads the notes"
}
check "AC2: A raft is one CLI session: the dispatcher's worker mode starts the raft's z-run session new, records its CLI and id in the run state, and resumes it (the CLI's resume flag, the same id) on a rerun on the same CLI; a raft the previous run held is carried on before \`next\` is asked; the state file names the item held while its chain runs and nothing held when it ends; the next raft is a run state of its own, so its session is new (the clearing)." ac2
ac3() {
	fixtureSpec command --run "AC3: --once with nothing claimable prints the summary and ends, starting no CLI"
	fixtureSpec loop "AC3: with nothing claimable the loop waits between polls with no dispatch run, and --once does not wait" "AC3: --max-items N ends the loop after N items" "AC3: a stop asked ends the worker after the dispatch run in progress and the raft stays held" "AC3: an item another worker holds is not taken, and the loop waits instead of spinning"
}
check "AC3: With nothing claimable the loop waits between polls with no dispatch run and so no model; \`--once\` never waits and \`--max-items\` ends the loop after that many items; a stop asked ends the loop after the dispatch run in progress and the raft stays held; an item whose lock another worker holds is not taken and is not spun on." ac3
ac4() {
	fixtureSpec loop "AC4: a blocked item is counted and the loop goes on to the next raft, which is taken" "AC4: two blocked items in a row stop the worker" "AC4: a failed chain is run again once with retry, and a second failure stops the worker naming the item" "AC4: a tripwire stops the worker, keeps the item held and names it"
	fixtureSpec pure "AC4: what a dispatch run's exit code asks of the loop"
}
check "AC4: The loop reads a dispatch run only by its exit code: done is moved, blocked (3) is counted and the next pick is taken, two blocked in a row stop the worker, a failure (1) is run again once with \`retry\` and a second stops the worker naming the item (the claim stays held), and a tripwire (5) stops it; the supervisor never gives a claim back with \`./zn stop\`." ac4
ac5() {
	fixtureSpec dispatch "AC5: every prompt of a worker session names its skill, the raft and the notes; a resumed one says so" "AC5: the person's CLI is tried first" "AC5: a CLI out of quota is waited for once, then the next CLI starts a new session that reads the notes" "AC5: a plain dispatch run keeps the role's order, with no wait and no session record"
	fixtureSpec pure "AC5: the person's CLI is tried first, and the first is waited for once before the next" "AC5: an outage is one unbroken stretch, and only past the cap is it a block; the note it files parses" "AC5: every prompt of a worker session names its skill and the notes, a resumed one says it has read it"
}
check "AC5: A CLI that says quota is waited for once, up to its \`quota_wait_minutes\`, then the next CLI starts a new session that reads the raft's \`notes.md\`; the person's CLI is tried first; every prompt of a worker session names its skill, the raft and the notes (a resumed one says it has read the skill); with every CLI out the dispatcher waits, forgets an outage a working session ended, and files a note \`escalation.parse\` accepts and runs \`./zn block <R> quota\` only past the cap, never when no cap is set." ac5
ac6() {
	fixtureSpec dispatch "AC6: every session leaves one measured row, with the adapter's tokens and the model"
	fixtureSpec pure "AC6: the dispatcher child starts without the starter's markers and session ids" "AC6: every supported CLI has a resume row, and a resumed session swaps or appends the flag"
	fixtureSpec session "AC6: the session has the dispatcher's wrapper, broker and the agent's token, and not the person's markers" "AC6: the session is told the model it runs on, so its spend and commits record the author"
}
check "AC6: Every session is the dispatcher's own step: the dispatcher's wrapper first on its PATH, a publish broker, the agent's token and never the person's, \`ZN_HEADLESS\` and \`ZN_MODEL\` set, none of the starter's markers or session ids (the supervisor starts the dispatcher with them cleared), and one measured row per session with the adapter's tokens and the model; every CLI in \`models.CLIS\` has a resume row." ac6
ac7() {
	fixtureSpec dispatch "AC7: the quota wait beats the claim through c0275's claimBeat, with the claim's stamp"
	fixtureSpec loop "AC7: a raft's pending gate is waited for and dispatched again, bounded by the clock, not by the number of runs" "AC7: a pending gate that clears ends the item as moved with no second session of ours" "AC7: a draft that waits for the person's approval is parked and the loop takes the next pick"
}
check "AC7: A raft's pending gate (CI, a merge) is waited for and dispatched again, bounded by the clock and not by a count of runs, and then stops the worker naming the raft; a draft that waits for the person's approval is parked and the next pick is taken; the dispatcher's quota wait beats the claim through c0275's claimBeat." ac7
ac8() {
	fixtureSpec loop "AC8: a host that does not land passes --no-run, so the run gate (the landing) stays off"
	fixtureSpec pure "AC8: a host the person marked as one that does not land keeps the run gate off; anything unreadable fails closed" "AC8: the run gate (the landing) is the only gate a host that does not land drops"
}
check "AC8: The supervisor never lands: the dispatcher's \`run\` gate does, under \`auto_merge\`, with the base's engine; a host marked \`[work] land = false\` in the user's own \`~/.config/zn/host.toml\` (anything unreadable counts as marked) passes \`--no-run\`, which drops only the \`run\` gate." ac8
ac9() {
	fixtureSpec command "AC9: a bare ./zn work and ./zn work <R-id> print the z-work skill, as before" "AC9: a boolean supervisor flag before a positional leaves the positional in place" "AC9: refuses a bad --max-items, an unknown option, and a CLI the roles do not name, before any claim" "AC9: the supervisor runs only in the main checkout" "AC9: it does not start inside a headless or dispatched session, and never detached inside a check" "AC9: work run is the same supervisor without a flag, and takes the CLI the roles name"
	fixtureSpec loop "AC9: a failed read of next is retried after a wait, never read as a pick or as nothing" "AC9: reads that keep failing stop the worker naming the error" "AC9: a Lune error that exits 1 is a failed read, not an empty stack"
	fixtureSpec pure "AC9: every other outcome of next is a failed read, never a pick and never nothing" "AC9: the CLI the person started is the one the supervisor runs, and it must be one every role has" "AC9: the supervisor starts only in the main checkout and never inside a session or (detached) a check"
}
check "AC9: \`./zn work\` with a supervisor flag (\`--cli\`, \`--once\`, \`--max-items\`, \`--detach\`) or \`./zn work run\` is the supervisor and a bare \`./zn work\` and \`./zn work <R-id>\` still print the z-work skill; a boolean flag before a positional leaves the positional in place; it starts only in the main checkout, never inside a headless or dispatched session, and never detached inside a check; a bad \`--max-items\`, an unknown option and a \`--cli\` that is not among the tries of every role are refused before anything starts; a failed \`next\` (a fetch, a Lune error that exits 1) is retried after a wait and never read as a pick or as nothing, and after five in a row stops the worker naming the error." ac9
ac10() {
	fixtureSpec board --run "AC10: a live supervisor is the dispatch row of the item it holds" "AC10: a stopped, a dead and an unreadable supervisor show nothing" "AC10: the dispatcher's own row for the item wins"
	fixtureSpec command "AC10: a stale stop file does not stop the next supervisor" "AC10: stop with no supervisor says so and writes nothing; status calls a dead one ended" "AC10: a second supervisor in one clone is refused while the first holds the lock"
	fixtureSpec pure "AC10: the state file reads back what was written, and a stale one is called ended" "AC10: the detached start leaves its own session, clears the markers and keeps the flags in the order typed" "AC10: the summary names what moved and what blocked"
	fixtureSpec reap --run "AC10: the supervisor is recognised by the command it runs, and only by that" "AC10: the orphaned supervisor the state file names is kept, and a stray orphan beside it is not" "AC10: a supervisor-looking process the state file does not name is a leak, and so is a named pid with another command" "AC10: what runs below the supervisor keeps every rule, the deadline included" "AC10: a supervisor a session started in the background (the window way) ends with that session, the detached one does not"
}
check "AC10: The supervisor writes its state (\`.cache/work/state\`, with the item held) and \`./zn work status\` prints it as one line (stopped, or ended with or without a summary); \`./zn work stop\` says so and writes nothing when no supervisor runs; a stale stop file does not stop the next supervisor; one supervisor per clone, enforced by a lock; \`--detach\` starts the same supervisor in a session of its own with the starter's markers cleared and the flags in the order typed; the reaper exempts only the supervisor the state file names and only from the orphan rule (what runs below it keeps every rule, a supervisor started in a session's background ends with it); the board shows the live supervisor on the card of the raft it holds; the summary names what moved and what blocked." ac10
ac11() {
	fixtureSpec models --run "AC11: is read per CLI, in seconds, the closest file winning" "AC11: refuses a CLI it does not support, an unknown key and a value that is not whole minutes" "AC11: leaves a file with no [work] table as it was"
}
check "AC11: \`.models.toml\` reads \`[work.<cli>] quota_wait_minutes\` per supported CLI, in seconds, the closest file winning, and refuses an unsupported CLI, an unknown key and a value that is not whole minutes, naming it." ac11
ac12() {
	fixtureSpec docs --run "AC12: the z-work skill puts the headless session first, starts the supervisor with the person's CLI, and ends a worker session at its raft" "AC12: the README's picture has the worker draft the design and the person approve it, and the worker section says what each way in does" "AC12: zz-rules, zz-test's reaper paragraph and the root rules file agree"
}
check "AC12: The z-work skill (the headless session first; the supervisor started with the person's CLI; a \`--here\` or \`/z-run\` session ends at its raft), the README (the workflow picture's design step, the worker section, \`./zn work run\`, the host file, the CPU limit), zz-rules, zz-test's reaper paragraph and the root rules file say what the supervisor does and no longer say what it overtook." ac12
ac13() {
	runRegression
}

check "AC13: The specs the change stands on stay green: the work and dispatch-text specs, the models, reap and tree specs, the scanning-loop and architecture meta-specs." ac13

finish
