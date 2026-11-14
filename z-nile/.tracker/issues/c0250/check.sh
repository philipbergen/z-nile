#!/usr/bin/env bash
# Acceptance checks for c0250. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0250 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0250"

# status.spec, escalation.spec, work-board.spec and docs.spec are plain specs. block-resolve.spec drives real git in a
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
check "AC1: blocked is a status with the edges preparing>blocked, active>blocked, blocked>new and blocked>prepared, stamped and parsed like the others; ./zn status neither blocks nor unblocks" ac1
check "AC2: escalation.luau parses and checks a note (every section, every option naming a decision, exactly one recommendation), stamps its header and one resume command per option, keeps the reason list closed, and maps each decision from preparing and from active to its status and edits" lune run tests/run -- "$A/escalation.spec.luau"
check "AC3: ./zn block <issue> <reason> on a preparing issue publishes one commit with the blocked status, blocked: <reason> and escalation.md, and refuses an unknown reason, a bad note and the main checkout" fixtureSpec block-resolve 'AC3: block on a preparing issue publishes one commit with the status, the reason and the note, and refuses a bad reason, a bad note and the main checkout'
check "AC4: ./zn block <R> <reason> on an active raft moves it and its active members to the backlog blocked (a member in done/ stays), adds the note, removes the prompt and claim file, names the parked branches and PRs and comments on the open layer's PR; a second block keeps the resolved note as escalation-NNN.md" fixtureSpec block-resolve 'AC4: block on an active raft moves it and its active members to the backlog blocked, keeps a done member, adds the note, removes the prompt, names the parked branch and comments on the PR' 'AC4: a second block keeps the resolved note as escalation-001.md'
check "AC5: ./zn resolve is refused with ZN_DISPATCH set, requires --said in an agent session and records it quoted, requires none in a terminal, and refuses an item that is not blocked" fixtureSpec block-resolve 'AC5: resolve is refused with ZN_DISPATCH, needs --said in an agent session and records it, needs none in a terminal, and refuses an item that is not blocked'
check "AC6: each decision moves the item as the table says, appends ## Resolution, removes blocked:, appends exactly one unblocked row to provenance.md and keeps rank:; amend-design and split on a raft take the Layer member out of the raft, split makes a new backlog issue and a Scope decision line, abort on a raft leaves it prepared and names the parked branches" fixtureSpec block-resolve 'AC6: each decision from preparing moves the issue as the table says, appends the resolution, removes blocked:, writes one unblocked row and keeps rank:' 'AC6: amend-design and split on a raft take the Layer member out of the raft, and split makes a new backlog issue and a Scope decision line' 'AC6: abort on a raft leaves it prepared and names the parked branches and PRs'
check "AC7: approve on a raft writes the Decided line in the Layer member, and ready refuses until that member is approved again; retry makes the raft prepared, and ready and start resume at the blocked layer on its parked branch" fixtureSpec block-resolve 'AC7: approve on a raft writes the Decided line in the Layer member, and ready refuses until that member is approved again' 'AC7: retry on a raft makes it prepared, and ready and start resume at the blocked layer on its parked branch'
check "AC8: a dispatched step that blocks stops the chain with exit 3 naming resolve; dispatch.next stops first on a blocked item; dispatch retry is refused while blocked, and after the resolve the re-run step's exchange holds the question and the resolution as its answer; --answer is refused for an item and kept for a capture" fixtureSpec dispatch-block --run 'AC8: a step that blocks stops the chain with exit 3 naming resolve, and next stops first on a blocked item' "AC8: retry is refused while blocked, and after resolve the re-run step's exchange holds the question and the resolution as its answer" 'AC8: --answer is refused for an item and kept for a capture' 'AC8: a nested step that needs the user tells its author to block the item'
check "AC9: a blocked raft is not claimable, whyNone and forRaft say so, and readycheck refuses it" fixtureSpec work-board --run 'AC9: a blocked raft is not claimable, whyNone and forRaft say so, and readycheck refuses it'
check "AC10: the board's first column is blocked, each card with its reason and question; ./zn list and ./zn status print blocked items first" fixtureSpec work-board "AC10: the board's first column is blocked, each card with its reason and question, and list and status print blocked items first"
check "AC11: quota_cap_hours is read from .models.toml, and a value that is not a whole number of at least 1 is refused, naming the key" fixtureSpec work-board 'AC11: quota_cap_hours is read and a bad value is refused naming the key'
check "AC12: zz-rules, the Headless paragraphs, z-work, z-stop, zz-review and the README say block and resolve, the quota row says the cap, and the README's next item is the next raft" lune run tests/run -- "$A/docs.spec.luau"
# the fast specs this change touches: of the listed specs, those not in the measured slow tier (tests/slow.tsv). The slow
# tier is the gate's, run by Implementation step 13 (z-nile/check.sh --slow), never by this check.sh.
fastSpecs() {
	local s
	for s in tests/acceptance/c0068/stop.spec.luau tests/acceptance/c0117/dispatch.spec.luau tests/acceptance/c0118/model.spec.luau tests/tooling/work.spec.luau tests/tooling/readycheck.spec.luau tests/tooling/approve.spec.luau; do
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
check "AC13: the fast specs this change touches (c0068/stop, c0117/dispatch, c0118/model, and the tooling work, readycheck and approve, those not in tests/slow.tsv) still pass" runFast

finish
