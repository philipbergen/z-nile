#!/usr/bin/env bash
# Acceptance checks for c0249. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0249 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0249"

# Six spec files hold the cases of ten criteria. command.spec builds one fixture whose cases build on each other, so every
# spec runs once (AC1's check does it) and each criterion then checks that each of its own cases passed: the runner writes
# a passing case's name to the --out file, but only when the whole run passes (z-nile/specs.luau), so one red case leaves
# the record empty and every criterion of that spec reports it (lesson zz-test/out-records-only-a-green-run): read the
# run's FAIL lines above, not the name a criterion reports.
OUT="$PWD/.cache/c0249-check"
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
	local rc=0
	fixtureSpec rank --run 'AC1: a rank is a whole number from 1 to 999999, and an empty value is unset' 'AC1: setting a rank writes one line before status, unsetting removes every rank line' 'AC1: a document path gives its state, id and root, and a done item is its id alone' 'AC1: only the backlog is ranked; an active or done item counts as unset' || rc=1
	fixtureSpec command --run || true
	fixtureSpec board --run || true
	fixtureSpec hash --run || true
	fixtureSpec app --run || true
	fixtureSpec docs --run || true
	return $rc
}
check "AC1: \`rank:\` in an issue's or a raft's front matter is a whole number from 1 to 999999 and nothing else (an empty value or no line is unset), setting a rank writes one line just before \`status:\` and unsetting removes every rank line, only a backlog item has a rank (an active or done item's counts as unset), and a document path gives its state, id and project root." ac1
ac2() {
	local rc=0
	fixtureSpec rank 'AC2: top, last, before and after put one item in a gap, so one move edits one file' 'AC2: a move that lands where the item already is changes nothing' 'AC2: with no gap, or among unset items, the items from the top through the moved one are renumbered 10, 20, 30' 'AC2: set and unset change the one item; a bad number or anchor is refused naming it' 'AC2: a move among rafts places a raft by its effective rank and gives it a rank of its own' || rc=1
	fixtureSpec command 'AC2: rank top, in the main checkout, publishes one commit and fast-forwards the checkout' 'AC2: after puts an item into a gap; a move to where it already is publishes nothing' 'AC2: the board app'\''s form, rank <id> --before <id>, works in a worktree, which merges origin/main' 'AC2: a move among unset items ranks the ones above it in the same commit, each with a ranked row' 'AC2: unset removes the line, and a number sets exactly that rank' 'AC2: a refused rank names the rule, publishes nothing and leaves the checkout alone' 'AC2: --before with an empty id puts the item last' || rc=1
	return $rc
}
check "AC2: \`./zn rank <id> top | last | before <id> | after <id> | <n> | unset\`, and the board app's \`rank <id> --before <id>\` (an empty id means last), give the item a rank in a gap between its neighbours (one file edited) or, with no gap or among unset items, renumber the items from the top through it in steps of 10; the change is one commit on \`origin/main\` holding the changed \`rank:\` lines and a \`ranked\` row of the live actor for each (a neighbour's names the item that moved it), it runs in the main checkout, which it only fast-forwards, and in a worktree, which merges origin/main, a move to where the item already is publishes nothing, and an item that is done, active, missing or of another kind, a bad number, anchor or option, a dirty main checkout and a missing id are refused with the rule and publish nothing." ac2
ac3() {
	local rc=0
	fixtureSpec rank 'AC3: a raft'\''s own rank overrides its members'\'', and an unset one takes their best' || rc=1
	fixtureSpec command 'AC3: a raft'\''s own rank overrides its members'\'', and an unset one takes their best' || rc=1
	return $rc
}
check "AC3: a raft's own rank overrides its members' ranks and an unset raft rank takes its members' best (an unset raft with no ranked member is unset), in the order, in the move (a raft is placed by its effective rank and given a rank of its own), in \`./zn next\` and in \`./zn work next\`." ac3
ac4() {
	local rc=0
	fixtureSpec rank 'AC4: next takes lost work first, whatever its rank, in the order given' 'AC4: next takes the claimable raft with the best rank, and an issue only when no raft is claimable' 'AC4: next skips an item that waits on undone work or is blocked, and its rank is left as it is' 'AC4: next takes only items in the backlog that are not claimed, and says why when there is none' 'AC4: next in a project'\''s folder takes that project'\''s items only' 'AC4: ./zn work next takes rafts in rank order too, an unset rank last and the number as the tiebreak' || rc=1
	fixtureSpec command 'AC4: next puts lost work first, whatever the rank, and not before the claim is stale' 'AC4: with no claimable raft next takes an issue to draft, skipping what waits, is blocked or is not ready' || rc=1
	return $rc
}
check "AC4: \`./zn next\` prints the next item as \`<id> lost|raft|draft <why>\`: lost work first in the heartbeat's order whatever its rank (and not before its claim is stale), else the claimable raft with the best rank, and only when no raft is claimable the best-ranked issue a worker may draft (not claimed, in no raft, its idea challenged); an item that waits on undone work (a raft: on a member's dependency outside it) or is blocked is skipped and keeps its rank; it takes one project's items from a project's folder, and says why there is none; \`./zn work next\` takes rafts in the same rank order." ac4
ac5() {
	local rc=0
	fixtureSpec rank 'AC5: blocked items come first when asked, and lost work comes first whatever its rank' || rc=1
	fixtureSpec command 'AC5: list shows blocked items first, then the stack in order, rafts before issues' || rc=1
	fixtureSpec board 'AC5: a column'\''s cards are ordered by rank, then ticket number, inside the bands and among them' 'AC5: board.collect gives every issue and raft its rank and orders the bands by it' || rc=1
	return $rc
}
check "AC5: \`./zn list\` shows rafts, then issues, each as the stack in order (blocked items first, then a set rank before an unset one, the lower first, then the ticket number), an item that is not in the backlog counting as unset, and the board's model gives every issue and raft its rank and the one the order uses and orders each column's raft bands and the cards in them the same way (a blocked band first); the order takes lost work first, and blocked first, when asked." ac5
ac6() {
	local rc=0
	fixtureSpec rank 'AC6: the audit'\''s check names a malformed, repeated or oddly written rank line, and passes the rest' || rc=1
	fixtureSpec command 'AC6: the audit rejects a malformed rank and names the item and the rule' || rc=1
	return $rc
}
check "AC6: \`./zn audit\` rejects, naming the item and the rule, a \`rank:\` that is not a whole number from 1 to 999999, a rank written twice and a rank line in a shape the readers would skip (indented, spaced before the colon, another case), and passes an empty rank, a valid one and a body that mentions rank." ac6
ac7() {
	local rc=0
	fixtureSpec app 'AC7: the shipped command, the rank order, a raft'\''s effective rank, junk ranks and the session order' || rc=1
	return $rc
}
check "AC7: the Omarchy board app orders tickets and rafts by the engine's rank (a set rank first, the lower first, the ticket number as the tiebreak, a raft by its effective rank, anything but a whole number from 1 to 999999 unset), ships \`rankCommand\` as \`./zn rank {id} --before {beforeId}\` (one argument per value, never a shell), shows a dragged order at once and drops it when a move is saved." ac7
ac8() {
	local rc=0
	fixtureSpec docs 'AC8: the README'\''s Order section says unset is valid, what claimable means and who sets a rank' 'AC8: zz-rules lists both commands where they may run and states the rank rule' 'AC8: z-ticket, z-design and z-raft say they write no rank, and the templates write none' 'AC8: the usage text lists rank and next' || rc=1
	return $rc
}
check "AC8: the README's Order section says every issue and raft can carry a rank, unset being valid, what claimable means, who sets a rank and that z-ticket, z-design and z-raft leave it unset (the older \"gets a rank\", \"append by default\" and \"z-raft asks\" lines are gone) and the roadmap row says it exists; zz-rules names both commands where they may run and states the rank rule; the three skills and z-work say it; the templates write no rank; the usage text lists both commands." ac8
ac9() {
	local rc=0
	fixtureSpec rank 'AC9: equal or unset ranks fall back to the ticket number, so the order is always stable' || rc=1
	return $rc
}
check "AC9: equal or unset ranks fall back to the ticket number, so the order is always stable: a set rank before an unset one, then the number across f, d and c, a raft before an issue, the id for one number in two kinds, and the same order whatever the input order." ac9
ac10() {
	local rc=0
	fixtureSpec command 'AC10: a rank on a grouped member changes neither its raft'\''s claimability nor its approval' || rc=1
	fixtureSpec hash 'AC10: designHash and recordHash leave the rank line out, and nothing else' 'AC10: the approval contract does not read the rank' 'AC10: the publisher takes a rank change on a backlog document, alone or with a status change' 'AC10: it refuses a rank change on an active or a done document, naming the file and the rule' 'AC10: it refuses two rank lines, and a rank change beside any other front-matter change' || rc=1
	return $rc
}
check "AC10: a \`rank:\` edit voids no design hash and no approval and the publisher takes it only for a backlog item: \`raftplan.designHash\` and a member's record leave the rank line out (and nothing else), the approval contract does not read it, \`publish.commit\` accepts a rank change on a backlog issue or raft (with or without a status change) and refuses it on an active or a done document, refuses two rank lines and any other front-matter change beside it, and a raft stays claimable after one of its grouped members is ranked." ac10

finish
