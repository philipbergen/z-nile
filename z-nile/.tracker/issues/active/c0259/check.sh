#!/usr/bin/env bash
# Acceptance checks for c0259. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `done`, promoted to its project's tests/acceptance/c0259 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0259"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
README="$ROOT/z-nile/README.md"

# Every literal the rules need, in the README's workflow section (this file, not the promoted spec, owns the vocabulary).
words() { local w; for w in "$@"; do grep -qF -e "$w" "$README" || { echo "README lacks: $w"; return 1; }; done; }
# The tracker's state of an issue: done = exists, design: ready = designed, else captured.
real() {
	local path
	path="$(cd "$ROOT" && "$ROOT/zn" find "$1" 2>/dev/null | head -1)"; [[ -n $path ]] || { echo missing; return; }
	if [[ $path == */done/* ]]; then echo exists
	elif grep -q '^design: ready' "$ROOT/$path/$1.md" "$path/$1.md" 2>/dev/null; then echo designed
	else echo captured; fi
}
# What the executor may not change is pinned here, in the order of the reviewed text: (sub-section | issue id or -) for every
# label, and the roadmap's issue column (column 2). The state words are read from the delivered README and each must equal
# the tracker's state of its issue, so a README that follows a tracker change passes and one that lags or runs ahead fails.
LABELS='Two ends, one stack|-
Two ends, one stack|c0253
Two ends, one stack|c0117
Two ends, one stack|c0254
Order|c0249
Claiming across hosts|c0254
Claiming across hosts|-
Autonomous delivery|c0252
Reviews by different models|c0251
Reviews by different models|c0117
Escalation to the human|c0250
Trust|c0117
Stacked delivery|c0248'
ROWS='c0117
c0118
c0142
c0248
c0249
c0250
c0251
c0252
c0253
c0254
c0258'
# The legend line is the one text exempt from the label scan, word for word; table rows are read by their issue column.
LEGEND="$(cat "$HERE/legend.txt")"
truth() {
	local bad=0 title="(intro)" line lab got="" states="" want state id
	while IFS= read -r line; do
		case $line in "### "*) title="${line#\#\#\# }"; continue;; "## The five parts"*) break;; "## "*) continue;; esac
		[[ $line == "$LEGEND" || $line == "| "* ]] && continue
		while IFS= read -r lab; do
			[[ -n $lab ]] || continue
			state="$(sed -E 's/^\*([a-z]+)\*.*/\1/' <<<"$lab")"; id="$(grep -o 'c[0-9]\{4\}' <<<"$lab" || true)"
			got+="$title|${id:--}"$'\n'; states+="${id:--} $state"$'\n'
		done < <(grep -oE '\*(exists|designed|captured)\*( \(c[0-9]{4}\))?' <<<"$line" || true)
	done < <(sed -n '/^## How it should work/,/^## The five parts/p' "$README")
	[[ "${got%$'\n'}" == "$LABELS" ]] || { echo "label places differ:"; diff <(printf '%s\n' "$LABELS") <(printf '%s' "$got"); bad=1; }
	got="$(sed -n '/^### Roadmap/,/^### Stacked/p' "$README" | grep '^| ' | grep -v -e '---' -e '| piece |' | awk -F'|' '{gsub(/ /,"",$3); print $3}')"
	[[ "$got" == "$ROWS" ]] || { echo "roadmap issues differ:"; diff <(printf '%s\n' "$ROWS") <(printf '%s\n' "$got"); bad=1; }
	states+="$(sed -n '/^### Roadmap/,/^### Stacked/p' "$README" | grep '^| ' | grep -v -e '---' -e '| piece |' | awk -F'|' '{gsub(/ /,"",$3); gsub(/ /,"",$4); print $3" "$4}')"$'\n'
	while read -r id state; do
		[[ -n $id ]] || continue
		if [[ $id == - ]]; then want=exists; else want="$(real "$id")"; fi
		[[ "$state" == "$want" ]] || { echo "$id: README says $state, tracker says $want"; bad=1; }
	done <<<"$states"
	return $bad
}
# The README changes only by the inserted section: it removes nothing and, with the section cut out, equals the branch point's.
removed() {
	local base
	base="$(git -C "$ROOT" merge-base origin/main HEAD)"
	diff <(awk '/^## How it should work$/{skip=1} /^## The five parts$/{skip=0} !skip' "$README") <(git -C "$ROOT" show "$base:z-nile/README.md") >/dev/null
}

check "AC1: every workflow sub-section carries a state label, and the section comes before The five parts" lune run tests/run -- "$A/readme.spec.luau"
check "AC2: the legend defines exactly three states and no other state word is used" lune run tests/run -- "$A/readme.spec.luau"
check "AC3: the roadmap is a table of rows with a defined state, one of them the stacked PR set" lune run tests/run -- "$A/readme.spec.luau"
check "AC4: the diagram fences are balanced and the diagram shows the engineer end and the worker end" lune run tests/run -- "$A/readme.spec.luau"
check "AC5: the README keeps what it said before" lune run tests/run -- "$A/readme.spec.luau"
check "AC6: the README states the rules: ranked order, the worker end, the claim, the merge, review by another family, escalation, stacked delivery" words \
	'`rank:`' '`depends_on`' '`./zn work`' 'The push is the lock' 'dispatcher merges' 'different model family' 'fallback' \
	'`blocked`' '`review-exhausted`' '`design-gap`' '`needs-decision`' '`red-gate`' '`quota`' '`tripwire`' '`escalation.md`' \
	'`./zn resolve' '`amend-design`' '`approve`' '`split`' '`retry`' '`abort`' 'stacked PR set' 'bottom-up' 'stack of one'
check "AC7: every roadmap row and every issue-labelled sentence has the state the tracker shows for its issue" truth
check "AC8: the README only gains the section: with it cut out the file equals the branch point's" removed

finish
