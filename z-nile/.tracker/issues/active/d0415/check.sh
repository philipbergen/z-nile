#!/usr/bin/env bash
# Acceptance checks for d0415. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0415 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0415"

# filing is a plain spec (pure functions over texts). dispatch drives `./zn dispatch zz-review` against fake CLIs in a
# fixture under .cache/d0415-dispatch, from a worktree of it (as c0117's dispatch-cli spec does); its cases build on one
# another (one raft, round after round), so it runs once and each criterion then checks that its own cases passed: the
# runner writes each passing case's name to the --out file, but only when the whole run passes (lesson
# zz-test/out-records-only-a-green-run): read the run's FAIL lines.
OUT="$PWD/.cache/d0415-check"
fixtureSpec() {
	local file="$1" home rel out
	shift
	home="$(pwd -P)"
	rel="${A#"$home"/}/$file.spec.luau" # the runner takes the spec's path from the project home
	out="$OUT/$file.txt"
	if [[ ${1:-} == --run ]]; then
		shift
		mkdir -p "$OUT" && : >"$out"
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
	fixtureSpec filing --run "AC1: a raft with no review files round 1" "AC1: a refolded raft, whose only review quotes the older record, files the next number" "AC1: the next number is one past the highest, not the count of files" "AC1: coveringReview names the first covering review in name order and ignores other files" || rc=1
	fixtureSpec dispatch --run "AC1: a refolded raft's review is filed as the next design-review-NNN.md and the older one is left as it was" || rc=1
	return $rc
}
check "AC1: in raft mode the dispatcher files the review as the next \`design-review-NNN.md\` whenever no review in the raft folder quotes the raft's current \`grouped:\` record." ac1
ac2() {
	local rc=0
	fixtureSpec filing "AC2: a review that quotes the current record is refused, naming the file, the record and the rule" "AC2: any one of several reviews quoting the current record refuses" "AC2: a review that quotes a record with one other hash does not cover it" "AC2: a review of a larger record covers a smaller one (an unfold alone needs no new review)" "AC2: a review that quotes no record covers none" "AC2: an older review that covers the record still refuses when a newer one quotes another record" "AC2: a raft with no grouped record keeps one round, as every other mode does" || rc=1
	fixtureSpec dispatch "AC2: the same record again is refused and no second review is filed" || rc=1
	return $rc
}
check "AC2: in raft mode the dispatcher still refuses a second review of a \`grouped:\` record that a review in the raft folder already quotes." ac2
ac3() {
	local rc=0
	fixtureSpec filing "AC3: a malformed grouped record is refused, naming the raft and the problem" "AC3: the one-round rule of every other mode is decided from the folder, and keeps its words" "AC3: another prefix's or another issue's files never count" || rc=1
	fixtureSpec dispatch "AC3: a raft refusal starts no CLI and spends zero tokens" "AC3: a design-mode second review is refused before any CLI starts, as is every refusal the folder decides" || rc=1
	return $rc
}
check "AC3: every refusal to file a review that can be decided from the folder's state is made before any reviewer CLI is started, and that run spends zero tokens." ac3
ac4() {
	fixtureSpec dispatch "AC4: a review that cannot be filed after the run is kept as review-unfiled-N.md, and the failure names it" "AC4: a later run of the same item neither deletes nor overwrites a kept review"
}
check "AC4: a review the dispatcher cannot file after the reviewer ran is moved to a numbered \`review-unfiled-N.md\` in the item's state folder (N one past the highest there), which no later run of the same item deletes or overwrites, and the failure message prints that path." ac4
ac5() {
	local rc=0
	fixtureSpec filing "AC5: a pending row says when it is written, from where its item stands on origin/main" "AC5: a raft row that names no members (recorded before d0415) is never written, and says so" || rc=1
	fixtureSpec dispatch "AC5: a raft's review row is written to its members the way ./zn spend shares it" "AC5: a row that cannot be recorded stays pending, is printed as unrecorded spend, and is listed by dispatch status" "AC5: a nested run's unrecorded row is listed by dispatch status and ./zn metrics, and a later run of the item writes it once" "AC5: a pending raft row recorded before this change is never written, and says so" || rc=1
	return $rc
}
check "AC5: a review run whose design-review row cannot be recorded leaves a pending row holding its tokens and minutes that \`./zn dispatch status\` and the run's own output show, and a raft's row is recorded on its members instead of being lost." ac5

finish
