#!/usr/bin/env bash
# Acceptance checks for c0250. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0250 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0250"

# status.spec, escalation.spec, publish.spec, audit.spec, work-board.spec and docs.spec are plain specs. block-resolve.spec drives real git in a
# fixture under .cache (a local bare origin whose path contains github.com, worktrees, a gh stub that records its calls)
# and dispatch-block.spec drives `./zn dispatch` with fake CLIs under .cache. Their cases build on each other, so each
# runs once, and every criterion then checks that each of its own cases passed: the runner writes each passing case's
# name to the --out file.
OUT="$PWD/.cache/c0250-check"
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
		grep -qxF "	$c" "$out" || { echo "did not pass: $c"; return 1; }
	done
}

# AC1 starts block-resolve.spec (--run); the later criteria read its record. The pure rules are status.spec's.
ac1() {
	fixtureSpec block-resolve --run 'AC1: ./zn status refuses to block' 'AC1: ./zn status refuses to unblock a blocked item and names resolve' && lune run tests/run -- "$A/status.spec.luau"
}
check "AC1: \`blocked\` is a status with the edges \`preparing>blocked\`, \`active>blocked\`, \`blocked>new\` and \`blocked>prepared\`, stamped and parsed like the others; \`./zn status\` neither blocks nor unblocks." ac1
check "AC2: \`escalation.luau\` parses and checks a note (every section, every option naming a decision, exactly one recommendation), stamps its header and one resume command per option, keeps the reason list closed, and maps each decision from \`preparing\` and from \`active\` to its status and edits." lune run tests/run -- "$A/escalation.spec.luau"
check "AC3: \`./zn block <issue> <reason>\` on a \`preparing\` issue publishes one commit with the \`blocked-…\` status, \`blocked: <reason>\` and \`escalation.md\`, and refuses an unknown reason, a bad note, a note that already holds a resolution, the main checkout, a member of an active raft (naming its raft) and the reason \`tripwire\` in an agent session; on a blocked item whose note is missing it re-files the note without a move." fixtureSpec block-resolve 'AC3: block on a preparing issue publishes one commit with the status, the reason and the note, and refuses a bad reason, a bad note and the main checkout' 'AC3: block refuses the reason tripwire in an agent session and files it from a terminal' 'AC3: block refuses a note that already holds a resolution' 'AC3: block refuses an issue that is a member of an active raft, naming the raft and --layer' 'AC3: block re-files the note of a blocked item whose note is missing or unreadable, without moving it'
check "AC4: \`./zn block <R> <reason>\` on an active raft moves it and its active members to the backlog blocked (a member in \`done/\` stays), adds the note to the raft's folder, removes the prompt and claim file, names the parked branches and PRs and comments on the open layer's PR; a second block keeps the resolved note as \`escalation-NNN.md\`; the Layer is \`--layer\`, required when two or more members are still in \`active/\`, or else the only member still there, never the current branch (after \`done --through\`, and from a detached worktree before \`start\`), a done \`--layer\` is refused, and the comment goes to the Layer's PR." fixtureSpec block-resolve 'AC4: block on an active raft moves it and its active members to the backlog blocked, keeps a done member, adds the note, removes the prompt, names the parked branch and comments on the PR' 'AC4: a second block keeps the resolved note as escalation-001.md' 'AC4: block from a detached worktree takes the only member still in active/ as the Layer, and --layer names one of several'
check "AC5: \`./zn resolve\` is refused with \`ZN_DISPATCH\` set, requires \`--said\` in an agent session and records it quoted, requires none in a terminal, refuses \`ZN_HEADLESS\`, a resolve from the session that filed the block and an item that is not blocked, needs one \`--rule\` per open id of a \`review-exhausted\` note, and quotes \`--said\` in an agent session's Decided line." fixtureSpec block-resolve 'AC5: resolve is refused with ZN_DISPATCH, needs --said in an agent session and records it, needs none in a terminal, and refuses an item that is not blocked'
ac6() {
	fixtureSpec block-resolve 'AC6: each decision from preparing moves the issue as the table says, appends the resolution, removes blocked:, writes one unblocked row and keeps rank:' 'AC6: amend-design and split on a raft take the Layer member out of the raft, and split makes a new backlog issue and a Scope decision line' 'AC6: a raft the Layer leaves with no unlanded member goes to done/ when a member landed and to retired/ when none did' 'AC6: abort on a raft leaves it prepared and names the parked branches and PRs' && lune run tests/run -- "$A/escalation.spec.luau"
}
check "AC6: each decision moves the item as the table says, appends \`## Resolution\`, removes \`blocked:\`, appends exactly one \`unblocked\` row to \`provenance.md\` and keeps \`rank:\`; \`amend-design\` and \`split\` on a raft take the \`Layer:\` member out of the raft, and \`split\` makes a new backlog issue and a \`Scope decision\` line; \`abort\` on a raft leaves it \`prepared\` and names the parked branches and PRs; the rulings are recorded and \`./zn rulings\` writes them as \`Ruled (user, …)\` lines; a raft the Layer leaves empty moves to \`done/\` or \`retired/\`; on a draft raft \`approve\` and \`amend-design\` act as \`retry\` and \`split\` is refused." ac6
check "AC7: \`approve\` on a raft writes the Decided line in the \`Layer:\` member, and \`ready\` refuses until that member is approved again; \`retry\` makes the raft \`prepared\`, and \`ready\` and \`start\` resume at the blocked layer on its parked branch; \`resolve approve\` re-records the member's \`grouped:\` so that \`ready\` passes after the user's approve; a raft with a landed member resumes at layer 2 and leaves the done member byte for byte unchanged." fixtureSpec block-resolve 'AC7: approve on a raft writes the Decided line in the Layer member, and ready refuses until that member is approved again' 'AC7: retry on a raft makes it prepared, and ready and start resume at the blocked layer on its parked branch' 'AC7: a raft with a landed member resumes at layer 2: ready moves only the unlanded members, start reuses the parked branch and PR, the done member is untouched'
check "AC8: a dispatched step that blocks stops the chain with exit 3 naming \`resolve\`; \`dispatch.next\` stops first on a blocked item; \`dispatch retry\` is refused while blocked, with or without an answer flag, and after the resolve the re-run step's exchange holds the question and the resolution as its answer; c0256's answer path stays beside the block for a capture and for an item whose step wrote \`questions.md\`; a finding still open at the round cap blocks with \`review-exhausted\`; a step that blocks and also leaves \`questions.md\` has the file set aside unread; \`./zn dispatch <id>\` after a resolve carries the resolution, on a host that never saw the block too, once; a one-step run on a blocked item starts nothing and one after the resolve carries it; a c0256 question still waiting at the resume is set aside and the resolution is its answer; an issue a blocked draft raft lists waits on the raft, and its next step carries the raft's resolution once; a resolved raft's z-run is told the resolution answers its own question; a dispatched z-run step blocks an active raft." fixtureSpec dispatch-block --run "AC8: a step that blocks stops the chain with exit 3 naming resolve, and next stops first on a blocked item" "AC8: retry is refused while blocked, and after resolve the re-run step's exchange holds the question and the resolution as its answer" "AC8: c0256's answer path stays beside the block: an item whose step wrote questions.md, and a capture, are answered with --answer" "AC8: a nested step that needs the user tells its author to block the item" "AC8: an unruled open list blocks with review-exhausted, and ./zn dispatch <id> after the resolve carries the resolution" "AC8: a step that blocks and also leaves questions.md: the block is the question, and the file is set aside unread" "AC8: the resolution reaches the next step on a host that never saw the block, once" "AC8: a step started by hand on a blocked item starts nothing, and one started after the resolve carries it" "AC8: a c0256 question still waiting when the item is resolved is set aside, and the resolution is the answer" "AC8: an issue a blocked draft raft lists waits on it, and its next step carries the raft's resolution once" "AC8: a dispatched z-run step blocks an active raft: the chain stops with exit 3 and the move is on origin/main" "AC8: a resolved raft's z-run is told the resolution answers its own question, on a host that never saw the block" "AC8: a review started on a layer of a readied raft that needs the user tells its author to block the raft, in the raft's folder"
check "AC9: a blocked raft is not claimable, \`whyNone\` and \`forRaft\` say so, and \`readycheck\` refuses it." fixtureSpec work-board --run 'AC9: a blocked raft is not claimable, whyNone and forRaft say so, and readycheck refuses it'
check "AC10: the board's first column is \`blocked\`, each card with its reason and question; \`./zn list\` and \`./zn status\` print blocked items first; a blocked raft's members are found by its \`issues:\`, \`raft-plan\` skips them and \`fold\` refuses them." fixtureSpec work-board "AC10: the board's first column is blocked, each card with its reason and question, and list and status print blocked items first" "AC10: raft-plan skips, and fold refuses, an issue that a blocked raft lists, naming the raft"
check "AC11: \`quota_cap_hours\` is read from \`.models.toml\`, and a value that is not a whole number of at least 1 is refused, naming the key." fixtureSpec work-board 'AC11: quota_cap_hours is read and a bad value is refused naming the key'
check "AC12: zz-rules, the Headless paragraphs, z-work, z-stop, zz-review and the README say block and resolve (c0256's bullet, sentence and help line kept whole beside them), \`review-exhausted\` is a finding still open when no further review round may run, the quota row says the cap, and the README's next item is the next raft; zz-execute, z-work and zz-rules say who files a tripwire block, that a dispatched step never runs \`./zn done\`, and when an agent may resolve." lune run tests/run -- "$A/docs.spec.luau"
# the fast specs this change touches: of the listed specs, those not in the measured slow tier (tests/slow.tsv). The slow
# tier is the gate's, run by Implementation step 13 (z-nile/check.sh --slow), never by this check.sh.
fastSpecs() {
	local s
	for s in tests/acceptance/c0068/stop.spec.luau tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0118/model.spec.luau tests/acceptance/f0399/pick.spec.luau tests/acceptance/f0399/docs.spec.luau tests/tooling/work.spec.luau tests/tooling/readycheck.spec.luau tests/tooling/approve.spec.luau; do
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
check "AC13: the fast specs this change touches still pass: \`c0068/stop\`, \`c0117/dispatch\`, \`c0118/model\`, \`f0399/pick\`, \`f0399/docs\`, and the tooling \`work\`, \`readycheck\` and \`approve\`, those of them not in \`tests/slow.tsv\` when it runs (the slow tier is the gate's, run by Implementation step 13)." runFast
check "AC14: the publish rule for a \`blocked\` or \`resolve\` commit accepts only its listed edits and refuses an edited Scope line, a removed Decided line, a Decided line outside the Problem, \`raft:\` changed on a non-member, a rewritten \`escalation-NNN.md\` and an edited note body." lune run tests/run -- "$A/publish.spec.luau"
check "AC15: \`./zn audit\` reports a \`blocked\` item without \`blocked:\` or a readable unresolved note, \`blocked:\` on an item that is not blocked, and a reason outside the list, each naming the command that clears it." lune run tests/run -- "$A/audit.spec.luau"
finish
