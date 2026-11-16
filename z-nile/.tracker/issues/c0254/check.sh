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
# Each spec file runs once (its cases build on each other: the race, layer and chain specs share a fixture), and every criterion
# then checks that each of its own cases passed: the runner writes each passing case's name to the --out file, but only when the
# whole run passes (z-nile/specs.luau), so one red case leaves the record empty and every criterion of that spec reports it
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
	fixtureSpec pure --run 'AC1: a claim step that exits 0 is won' 'AC1: the dispatcher asks origin/main after a failed claim step, and only for a claim step' 'AC1: a lost claim leaves no failed step behind in the run state' 'AC1: a worker'\''s issue is claimed by its own step before any model starts' 'AC1: the dispatcher and the supervisor share one exit code for a lost race' 'AC1: the same item lost twice in a row waits one idle period instead of spinning' 'AC1: a run that lost nothing prints the summary it printed before' 'AC1: a failed claim is lost only when origin/main shows the item moved under another stamp' 'AC1: a failed claim that moved nothing or that cannot be read is a failure, and one whose stamp is this worker'\''s is ours' 'AC1: a lost race takes the next pick at once, is not a failure and is not counted as an item taken'
	fixtureSpec pick --run 'AC1: a draft pick is still ours only while the issue is new or carries our own stamp' 'AC1: a rafting pick is taken when a preparing raft that is not ours lists the issue' 'AC1: a plain dispatch of the same facts behaves as before' 'AC1: lost, then another item, then lost again is not two losses in a row' 'AC1: a raft the previous run held that turns out to be taken is no longer held' 'AC1: a raft pick is still ours only while the raft waits prepared in the backlog or carries our own stamp' 'AC1: a lost pick is left to the takeover'\''s lease, and a claim already ours stays ours only by its stamp' 'AC1: a worker'\''s draft or raft that another worker holds ends the run with the taken exit before any step' 'AC1: a lost pick is taken over by the claim step (an issue) or a stop then a ready (a raft); an owned raft runs' 'AC1: a claim whose commit carries this attempt'\''s token is ours even when no memory says so' 'AC1: a rafting step is lost only when a preparing raft that is not this run'\''s lists the issue' 'AC1: a claim that landed is recorded in the run state and in c0274'\''s claim memory of the worktree that works it' 'AC1: the supervisor passes the pick'\''s kind to the dispatcher, and reads the new exit codes' 'AC1: a z-design prompt of a worker'\''s run says the issue is already claimed, and a plain run'\''s does not'
	fixtureSpec race --run 'AC1: the claim is the push: host A wins, host B is refused and publishes nothing' 'AC1: a claim this checkout already holds is an idempotent success, so a session'\''s own claim passes' 'AC1: two hosts rafting one approved issue meet at the lease: the second `new raft` is refused and publishes nothing'
	fixtureSpec chain --run 'AC1: a plain dispatch of the same item is as it was: a failure, not the taken exit' 'AC1: a raft host A readied first ends host B'\''s run with exit 6, and no session runs on it' 'AC1: an issue host A claimed first ends host B'\''s run with exit 6 before any step, starting no session' 'AC1: a race lost between the pick and the claim step ends the run `taken` and leaves nothing on the losing host'
}
check "AC1: In worker mode the claim is the push and a rejected claim means taking the next raft, at every point of the race window: the dispatcher reads the pick on \`origin/main\` before any step and ends the run with exit 6 (\`taken\`) when a draft is no longer new or ours, a raft is no longer prepared in the backlog or ours, or a rafting issue is listed by a raft that is not ours; a worker owns a claim by the stamp its claim step recorded, never by the run state's history; it claims an issue with its own \`claim\` step before any model starts (and takes a lost pick over by \`claim\`, or \`z-stop\` then \`z-ready\`); a failed claim step is judged on \`origin/main\` as ours (the claim landed: adopted, the chain goes on), lost (exit 6, no failed step in the run state, no worktree or branch left on the losing host) or a failure; two hosts rafting one issue meet at the lease and the second is refused; a model's own \`./zn status <id> preparing\` after the dispatcher's claim is an idempotent success; and the supervisor counts a lost race, asks \`./zn next\` again at once (waiting one idle period only when the same item is lost twice with nothing between), does not count it as an item taken and clears a held raft that turns out taken." ac1
ac2() {
	fixtureSpec pure 'AC2, AC3: a worker whose claim was taken over or ended never pushes the branch' 'AC2, AC3: nothing is pushed over commits origin has, or when they cannot be counted' 'AC2: the claim states xhost reads are heartbeat.holds'\''s'
	fixtureSpec pick 'AC2: a lost worker is told c0274'\''s own words and to stop, never to continue on the taker'\''s branch' 'AC2: a numbered copy that holds no claim never pushes an item that is under a live claim, a layer'\''s included' 'AC2, AC7: staleMember is c0277'\''s rule: a worktree is stale when a claim it remembers is over and none is still its own'
	fixtureSpec race 'AC2: host B'\''s stale worktree, made by its lost claim step, is brought forward to host A'\''s push, not discarded' 'AC2: a local branch that has diverged from the pushed one is refused, and nothing local is discarded' 'AC2, AC3: host A'\''s next commit stands, is refused with c0274'\''s words and exit 7, and origin keeps the taker'\''s tip' 'AC2: a numbered copy of the lost worktree remembers no claim and does not push the taken prep either'
	fixtureSpec layer --run 'AC2, AC3: host A'\''s next commit stands, is refused with c0274'\''s words, exits 7, and origin keeps the taker'\''s tip' 'AC2: host A'\''s finish and restack are refused before they touch anything, and the taker'\''s commit survives' 'AC2: a numbered copy of the lost worktree remembers no claim and does not push the taken layer either'
}
check "AC2: The lost worker's worktree is not reused by another host and the lost worker cannot move the taker's work: a worktree is local to its clone and a taker builds its own from the pushed branch (a stale local branch is brought forward to origin, a diverged one is refused and nothing local is discarded); a worker whose claim was taken over or has ended, and a checkout that holds no claim on an item under a live one (a numbered copy included), never pushes, finishes or restacks a layer or prep branch; the refusal is c0274's own words and tells the worker to stop, never to continue on the taker's branch; and the taker's pushed commit survives the lost worker's \`finish\` and \`restack\`." ac2
ac3() {
	fixtureSpec pure 'AC3: every commit on a layer or prep branch is pushed, a first push sets the upstream' 'AC2, AC3: a worker whose claim was taken over or ended never pushes the branch' 'AC2, AC3: nothing is pushed over commits origin has, or when they cannot be counted' 'AC3: any other branch keeps today'\''s rule: pushed only with an upstream, and never main' 'AC3: branch kinds, and the claim each is keyed by'
	fixtureSpec pick 'AC3: the exit codes of a push are distinct from every dispatch code the supervisor reads as moved'
	fixtureSpec race 'AC3: a push that fails exits 8 after the commit, says so, and the next commit pushes both' 'AC3: host A'\''s prep commits are pushed one by one to the branch'\''s own name, the first sets the upstream' 'AC3: a worker that still holds its claim does not push over commits origin has and it lacks' 'AC3: the push goes to the branch'\''s own name whatever push.default and the upstream say, and main does not move' 'AC2, AC3: host A'\''s next commit stands, is refused with c0274'\''s words and exit 7, and origin keeps the taker'\''s tip'
	fixtureSpec layer 'AC3: a layer commit is pushed to its own branch, and main does not move' 'AC2, AC3: host A'\''s next commit stands, is refused with c0274'\''s words, exits 7, and origin keeps the taker'\''s tip'
}
check "AC3: Every commit is pushed, for layers and preps alike: after each \`./zn commit\` on a layer branch or in a \`prep-<slug>\` worktree the branch is pushed to its own name (whatever \`push.default\` and the upstream say, and never \`main\`) and the first push sets its upstream; the per-commit read of origin's copy never refreshes the ref \`finish\` and \`restack\` lease against; nothing is pushed for a taken or ended claim, for a checkout that holds none, over commits origin has and the worktree lacks, or when that cannot be counted; any other branch keeps today's rule; the commit always stands, and the exit says what happened to the push (7 refused under a claim, 8 failed; under dispatch a refusal is also written to \`.cache/push-refused\` and stops the run naming it)." ac3
ac4() {
	fixtureSpec pure 'AC4: a worker'\''s identity is its host, CLI and model' 'AC4: a person'\''s session has its CLI detected, and what nothing says is unknown'
	fixtureSpec chain 'AC4, AC5: the claim step runs as the worker that follows it, the model'\''s own claim passes, and the rows carry the step'\''s CLI'
	fixtureSpec spend --run 'AC4: a row with a host and a CLI is written with two more cells and reads back whole' 'AC4: a row that already says its host and CLI keeps them' 'AC4: with no CLI named and no marker the CLI cell says unknown, never a guess' 'AC4: a file with the old header still reads, and takes new rows without losing their host and CLI' 'AC4: the fold stamps every row it writes with this host and the step'\''s CLI, next to its model' 'AC4: a line a dispatched step wrote carries that step'\''s CLI through the buffer and into the row' 'AC4: the environment names the CLI only for the authoring phases, never for a reviewer'\''s row'
}
check "AC4: Spend rows record host, CLI and model, taken from the step and not from the process that folds the row: a row carries this machine's host and the CLI of the attempt that spent it (a dispatched step's own, a code-review row's reviewer included), and the environment names the CLI only for the authoring phases; a worker's claim runs as the worker whose session follows it (its CLI and model in the claim's trailer); an old spend file with the old header still reads and takes new rows without changing the old ones; and a dispatched run started inside another CLI's session still records the step's CLI." ac4
ac5() {
	fixtureSpec pure 'AC5: the Worker trailer round-trips and reads the newest holder of the item'\''s current stamp' 'AC5: ./zn work status names the worker that holds each raft, and says nothing extra when none is known'
	fixtureSpec pick 'AC5: a trailer may carry the attempt token, and the newest one for a stamp is found' 'AC5: a raft and each member a rafting claim stamped are named, one trailer line each'
	fixtureSpec race 'AC5: the claim commit says who made it, with the attempt, and the board reads it back' 'AC5: the rafting claim names its worker too, the raft and the member it stamped'
	fixtureSpec chain 'AC4, AC5: the claim step runs as the worker that follows it, the model'\''s own claim passes, and the rows carry the step'\''s CLI'
}
check "AC5: The board shows which worker holds what: every claim commit (an issue's, a raft's, a rafting \`new raft\`, \`fold\`, \`unfold\`, \`recombine\`, \`status\` and \`ready\`) carries a \`Worker: <id> <stamp> host=<h> cli=<c> model=<m> attempt=<token>\` trailer for each item it stamps, and the board's card and \`./zn work status\` name the worker of the newest trailer that carries the item's current stamp; a claim taken over names the new worker, and a stamp no trailer carries has no holder." ac5
ac6() {
	fixtureSpec docs --run 'AC6: the claim paragraph follows the raft claim and says what a preparing claim is' 'AC6: the done c0264'\''s pins hold: its phrase, its label place, and the capability row' 'AC6: the paragraph names the pushes, the exits, the trailer, the spend cells, the leftover and where who-holds-what shows' 'AC6: zz-rules says a prep commit is pushed, names the claim step, and states the several-hosts rules' 'AC6: z-design commits as it goes at named checkpoints, and skips the claim a worker'\''s dispatcher made'
}
check "AC6: The docs say it: the README's claim paragraph follows the raft claim (\"a lost race means taking the next raft\") and says a \`preparing\` claim is a worker drafting the design for a person to approve, and names the exits, the pushes, the trailer, the spend cells, the leftover and where who-holds-what shows; the phrases and the label place the done c0264's \`check.sh\` pins stay; zz-rules names the \`claim\` step and the several-hosts rules; z-design commits at named checkpoints and skips the claim the dispatcher made; the old wording is gone." ac6
ac7() {
	fixtureSpec pick 'AC2, AC7: staleMember is c0277'\''s rule: a worktree is stale when a claim it remembers is over and none is still its own'
	fixtureSpec race 'AC7: a discarded worktree is kept while the taker'\''s claim lives, and listed' 'AC7: host A'\''s sync marks its worktrees whose claims host B took over as discarded, with no copy' 'AC7: when the work ends, a clean worktree whose commits are all on origin is removed, and one holding an unpushed commit is kept and listed'
}
check "AC7: Q5's leftover on the lost host: \`./zn sync\` marks a layer or prep worktree whose claim another host took over (or that ended) as discarded, with no copy; it is kept while the taker's claim lives and when it holds uncommitted files or commits no origin ref has (and listed), and removed once the work has ended and nothing is left to recover; a host's own claims are never marked." ac7
# AC8: c0253's acceptance specs (sequestered, or promoted after its done) and the tooling specs that read the files this touches
ac8() {
	# c0253's specs are in its folder while it is sequestered or active, and in its project's tests/acceptance once it is done
	local c53=() d id=c0253 item
	item="$(cd "$ZN_ROOT" && "$ZN_ROOT/zn" find "$id" | head -1)"
	for d in "$ZN_ROOT/$item/acceptance" "$PWD/tests/acceptance/$id"; do
		if [[ -d $d ]]; then
			c53=("$d"/*.spec.luau)
			break
		fi
	done
	((${#c53[@]} > 0)) || { echo "c0253's acceptance specs were not found"; return 1; }
	lune run tests/run -- "${c53[@]#"$PWD"/}" tests/tooling/spend.spec.luau tests/tooling/board.spec.luau tests/tooling/work.spec.luau tests/tooling/dispatch-texts.spec.luau tests/tooling/measure.spec.luau tests/tooling/claim-taken.spec.luau tests/tooling/status-fresh.spec.luau tests/tooling/dispatch-guards.spec.luau tests/tooling/worktree-fetch.spec.luau tests/tooling/stack-land.spec.luau tests/tooling/start-pr-reuse.spec.luau
}
check "AC8: The specs this change stands on still pass: c0253's acceptance specs (the supervisor, the dispatcher's worker mode, the board row, the loop), run in whichever place they are, and the tracker, board, spend, work, dispatch and measurement specs that read the files it touches." ac8

finish
