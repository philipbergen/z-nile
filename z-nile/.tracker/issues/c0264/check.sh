#!/usr/bin/env bash
# Acceptance checks for c0264. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `done`, promoted to its project's tests/acceptance/c0264 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0264"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
README="$ROOT/z-nile/README.md"

# Every literal the rules need (this file, not the promoted spec, owns the vocabulary).
words() { local w; for w in "$@"; do grep -qF -e "$w" "$README" || { echo "README lacks: $w"; return 1; }; done; }
# The tracker's state of an issue: done = exists, design: ready = designed, else captured.
real() {
	local path
	path="$(cd "$ROOT" && "$ROOT/zn" find "$1" 2>/dev/null | head -1)"; [[ -n $path ]] || { echo missing; return; }
	if [[ $path == */done/* ]]; then echo exists
	elif grep -q '^design: ready' "$ROOT/$path/$1.md" "$path/$1.md" 2>/dev/null; then echo designed
	else echo captured; fi
}
# Pinned in the order of the reviewed text: (sub-section | issue id or -) for every label in How it should work, and the
# roadmap's issue column. The state words are read from the delivered README and each must equal the tracker's state of
# its issue, so a README that follows a tracker change passes and one that lags or runs ahead fails.
LABELS='Two ends, one stack|-
Two ends, one stack|c0253
Two ends, one stack|c0117
Two ends, one stack|c0254
The idea stage|c0260
The idea stage|c0247
The worker|c0253
The worker|c0175
Order|c0249
Order|c0265
Order|c0257
Claiming across hosts|c0254
Claiming across hosts|-
Claiming across hosts|c0265
Autonomous delivery|c0252
Model tiers|c0261
Reviews by different models|c0251
Reviews by different models|c0117
The full-force review|c0262
Escalation to the human|c0250
Provenance|c0263
Trust|c0117
Stacked delivery|c0248'
ROWS='c0117
c0118
c0142
c0175
c0247
c0248
c0249
c0250
c0251
c0252
c0253
c0254
c0257
c0258
c0260
c0261
c0262
c0263
c0265'
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
# The diagram of How it should work shows the new flow: the interview, the approval, z-work, lost-first claiming, one
# ticket at a time with the full-force review, and both ways a raft ends, as edges back into claiming (node ids `stack`,
# `loop`, `layer` and `esc` are fixed by the design; this file owns the words).
diagram() { sed -n '/^## How it should work/,/^## The five parts/p' "$README" | sed -n '/^```mermaid/,/^```$/p'; }
pictured() { local d w; d="$(diagram)"; for w in "$@"; do grep -qF -e "$w" <<<"$d" || { echo "diagram lacks: $w"; return 1; }; done; }
# The README changes only in ## Intent (new) and ## How it should work: with both cut out it equals the branch point's
# README with its How it should work cut out.
cut() { awk '/^## (Intent|How it should work)$/{skip=1; next} /^## /{skip=0} !skip'; }
others() {
	local base
	base="$(git -C "$ROOT" merge-base origin/main HEAD)"
	diff <(cut <"$README") <(git -C "$ROOT" show "$base:z-nile/README.md" | cut)
}

check "AC1: ## Intent comes after the opening picture and before How it should work" lune run tests/run -- "$A/intent.spec.luau"
check "AC2: the intent names the two human stages, the worker, the full-force review, the economy and the names" lune run tests/run -- "$A/intent.spec.luau"
check "AC3: the intent claims nothing as built" lune run tests/run -- "$A/intent.spec.luau"
check "AC4: the idea stage, the worker, model tiers, the full-force review and provenance are sub-sections, each labelled with its issue" lune run tests/run -- "$A/intent.spec.luau"
check "AC5: a worker clears its context and takes the next raft whenever a raft ends, merged or blocked" lune run tests/run -- "$A/intent.spec.luau"
check "AC6: the README states the rules of the worker model" words \
	'`z-work`' '`kimi`' '`agy`' '`deepseek`' 'stays with it all the way to merge' 'one ticket at a time' \
	'clears its context and picks up the next raft whenever a raft ends' 'It lets go of a raft only when the raft is blocked' \
	'marks the raft blocked' 'verbatim' 'every question z-ticket asked with its answer' 'confirms the idea' \
	'acceptance tests as code' 'cheap, sharp and wait' '4.6 at high' '4.7 at xhigh' 'Haiku' 'composer' \
	'never orchestrates and never waits' 'limited view' 'stayed on course' 'Off course means a redo' \
	'An unset `rank:` is the lowest rank' 'fall back to the ticket number' 'Lost work comes first' 'every 5 minutes' \
	'z-raft asks for a raft' 'drag and drop' 'Whose idea it was comes from git' 'who approved the design' 'who unblocked it' \
	'each ticket is worked to completion before the next is picked up, by the same worker' \
	'once a person has approved its design'
check "AC7: every roadmap row and every issue-labelled sentence has the state the tracker shows for its issue" truth
check "AC8: the README changes only in Intent and How it should work" others
check "AC9: the workflow diagram shows the interview, the approval, z-work, lost first, one ticket at a time, the full-force review and both ways a raft ends" pictured \
	'interview' 'idea review' 'approve' 'z-work' 'lost first' 'one ticket at a time' 'full-force review' \
	'stack --> loop' 'loop --> layer' 'layer -->|"raft merged: clear context"| loop' 'esc -->|"raft released: clear context"| loop'

finish
