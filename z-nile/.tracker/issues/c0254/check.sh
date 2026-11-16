#!/usr/bin/env bash
# Acceptance checks for c0254. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0254 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0254"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# Each spec file runs once (its cases build on each other: the race spec shares a fixture), and every criterion then checks
# that each of its own cases passed: the runner writes each passing case's name to the --out file, but only when the whole
# run passes (z-nile/specs.luau), so one red case leaves the record empty and every criterion of that spec reports it
# (lesson zz-test/out-records-only-a-green-run): read the run's FAIL lines.
OUT="$PWD/.cache/c0254-check"
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
	fixtureSpec pure --run 'AC1: a claim step that exits 0 is won' 'AC1: a failed claim is lost only when origin/main shows the item moved under another stamp' 'AC1: the dispatcher asks origin/main after a failed claim step, and only for a claim step' 'AC1: a worker'\''s issue is claimed by its own step before any model starts' 'AC1: the dispatcher and the supervisor share one exit code for a lost race' 'AC1: a lost race takes the next pick at once, is not a failure and is not counted as an item taken' 'AC1: the same item lost twice in a row waits one idle period instead of spinning' 'AC1: a run that lost nothing prints the summary it printed before' 'AC1: a failed claim that moved nothing, that cannot be read, or whose stamp is this worker'\''s is a failure'
	fixtureSpec race --run 'AC1: the claim is the push: host A wins, host B is refused and publishes nothing'
}
check "AC1: In worker mode the claim is the push and a rejected claim means taking the next raft: the dispatcher claims an issue with its own \`claim\` step before any model starts; a failed \`claim\` or \`z-ready\` step is asked about on \`origin/main\` and counts as lost only when the item left the state it was picked in under a stamp that is not the worker's own (any other failure stays a failure); a lost race ends the run with exit 6 (\`taken\`) and leaves no failed step in the run state; the supervisor counts it, asks \`./zn next\` again at once (one idle period only when the same item is lost twice running) and does not count it as an item taken; and with two clones of one origin the first claim wins and the second is refused and publishes nothing." ac1
ac2() {
	fixtureSpec pure 'AC2, AC3: a worker whose claim was taken over or ended never pushes the branch' 'AC2, AC3: nothing is pushed over commits origin has, or when they cannot be counted' 'AC2: the claim states xhost reads are heartbeat.holds'\''s'
	fixtureSpec race 'AC2: a taker on host B continues in a worktree of its own, built from the pushed branch' 'AC2, AC3: once host B holds the claim, host A'\''s next commit stays local and origin keeps B'\''s branch' 'AC2, AC3: a worker that still holds its claim does not push over commits origin has and it lacks'
}
check "AC2: The lost worker's worktree is not reused by another host: a taker on another host builds a worktree of its own, in its own clone, from the branch the lost worker pushed (it has every pushed commit and the lost worker's worktree is untouched), and a worker whose claim was taken over or has ended is never pushed again, so it cannot move the taker's branch." ac2
ac3() {
	fixtureSpec pure 'AC3: every commit on a layer or prep branch is pushed, a first push sets the upstream' 'AC2, AC3: a worker whose claim was taken over or ended never pushes the branch' 'AC2, AC3: nothing is pushed over commits origin has, or when they cannot be counted' 'AC3: any other branch keeps today'\''s rule: pushed only with an upstream, and never main' 'AC3: branch kinds, and the claim each is keyed by'
	fixtureSpec race 'AC3: host A'\''s prep commits are pushed one by one, the first sets the upstream' 'AC2, AC3: once host B holds the claim, host A'\''s next commit stays local and origin keeps B'\''s branch' 'AC2, AC3: a worker that still holds its claim does not push over commits origin has and it lacks'
}
check "AC3: Every commit is pushed, for layers and preps alike: after each \`./zn commit\` on a layer branch or in a \`prep-<slug>\` worktree the branch is pushed and the first push sets its upstream; nothing is pushed for a taken or ended claim, over commits origin has and the worktree lacks, or when that cannot be counted; any other branch keeps today's rule (pushed only with an upstream, never main); a refused push is said and the commit stands." ac3
ac4() {
	fixtureSpec pure 'AC4: a worker'\''s identity is its host, CLI and model' 'AC4: a person'\''s session has its CLI detected, and what nothing says is unknown'
	fixtureSpec spend --run 'AC4: a row with a host and a CLI is written with two more cells and reads back whole' 'AC4: a file with the old header still reads, and takes new rows without losing their host and CLI' 'AC4: the fold stamps every row it writes with this host and the step'\''s CLI, next to its model' 'AC4: a row that already says its host and CLI keeps them' 'AC4: with no CLI named and no marker the CLI cell says unknown, never a guess' 'AC4: the dispatcher sets the CLI of each attempt next to its model'
}
check "AC4: Spend rows record host, CLI and model: a row written by a fold carries this machine's host and the CLI of the step (\`ZN_CLI\`, set by the dispatcher for each attempt, else the CLI's markers, else \`unknown\`) beside its model cell; a row that already names them keeps them; an old file with the old header still reads and takes new rows, and the rows already in it are not changed." ac4
ac5() {
	fixtureSpec pure 'AC5: the Worker trailer round-trips and reads the newest holder of the item'\''s current stamp' 'AC5: ./zn work status names the worker that holds each raft, and says nothing extra when none is known'
	fixtureSpec race 'AC5: the claim commit says who made it, and the board reads it back' 'AC5: the board'\''s card for the issue says which worker holds it'
}
check "AC5: The board shows which worker holds what: a claim commit carries a \`Worker: <id> <stamp> host=<h> cli=<c> model=<m>\` trailer, and the board's card and \`./zn work status\` name the worker of the newest trailer that carries the item's current stamp (host, CLI, model); a claim taken over names the new worker, and a stamp no trailer carries has no holder." ac5
ac6() {
	fixtureSpec docs --run 'AC6: the claim paragraph follows the raft claim and says what a preparing claim is' 'AC6: the paragraph names the pushes, the trailer, the spend cells and where who-holds-what shows' 'AC6: the capability table lists the feature as built' 'AC6: zz-rules and z-design say a prep commit goes through ./zn commit and is pushed'
}
check "AC6: The docs say it: the README's claim paragraph follows the raft claim (\"a lost race means taking the next raft\") and says a \`preparing\` claim is a worker drafting the design for a person to approve, and it names the pushes, the trailer, the spend cells and where who-holds-what shows; zz-rules and z-design say a prep commit goes through \`./zn commit\` and is pushed; the old wording is gone." ac6
# AC7: the specs the change stands on, from the affected selector's list for its touched modules
runRegression() {
	lune run tests/run -- tests/tooling/spend.spec.luau tests/tooling/board.spec.luau tests/tooling/work.spec.luau tests/tooling/dispatch-texts.spec.luau tests/tooling/measure.spec.luau tests/tooling/claim-taken.spec.luau tests/tooling/status-fresh.spec.luau tests/tooling/dispatch-guards.spec.luau
}
check "AC7: The specs this change stands on still pass: the tracker, board, spend, dispatch, work and measurement specs that read the files it touches." runRegression

finish
