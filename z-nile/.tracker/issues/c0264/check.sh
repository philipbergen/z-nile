#!/usr/bin/env bash
# Acceptance checks for c0264. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0264 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0264"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
README="$ROOT/z-nile/README.md"

# The texts the README must carry, word for word. They live here, in the sequestered check.sh, so the executor cannot change
# what it is held to, and no promoted spec pins them, so later edits need no override. A status label in them is written
# *STATE* (cNNNN): its word is read from the tracker below (the c0259 rule), so a ticket that is designed or done by then
# is labelled so and still passes.
IFS= read -r -d '' INTENT <<'TXT'
## Intent
z-nile exists to move all human interaction up to the idea and the design, and to have workers carry everything else to the merge, at a low cost.
- **Humans at the idea and the design.** A person talks the idea through with the AI in plan mode, settles what is asked and approves the design; a worker may draft the design. `z-ticket` captures the idea, `z-design` sharpens it into a prepared issue and its design review. Nothing is designed past a person's ask.
- **Workers from the raft to the merge.** A worker takes a raft, stays with it until it merges, and works its tickets one at a time, each to completion before the next, through ready, run, review, the final review, gate and merge. It lets go only when the raft is blocked (Escalation to the human); it then clears its context and takes the next raft, and so it does whenever a raft merges.
- **Cheap on the way, sharp at the end.** Expensive models run every final review; cheaper, faster models do the work on the way there, and the cheapest do the waiting. Nothing expensive orchestrates or waits. Rigor does not move: the checks, the gate and the review rounds still run.

This section is the aim and carries no status label. How it should work, below, labels each part as exists, designed or captured; where an older line below that names the same ticket and one of the sub-sections from The worker, z-work to The board app (added for the 2026-11-07 ask) differ, the sub-section follows the ticket's current capture, and where a line has a worker design, it means a draft that a person approves.
TXT
IFS= read -r -d '' SECTIONS <<'TXT'
### The worker, z-work
A person starts any CLI by hand (kimi, agy, claude, grok, agent, deepseek) and runs `z-work`, and that agent becomes a worker. It picks up a raft, the first claimable one in the order (Rank and lost work, below), and moves it forward. It stays with the raft all the way to merge and delivers it as a PR stack, one ticket at a time, each worked to completion before the next is picked up. It beats every 5 minutes while it holds a raft. The headless `./zn work` is the same worker launched without a person, and a CLI that cannot read skills gets the same instructions printed by a `./zn` command. The worker itself runs on a cheap model and never orchestrates or waits on an expensive one. *STATE* (c0253); the PR stack *STATE* (c0248); the beat *STATE* (c0265); the six CLIs *STATE* (c0175); the worker running cheap *STATE* (c0261)

### When a raft ends, the worker moves on
Whenever a raft's last layer merges, or the raft is blocked and released, the worker clears its context and picks up the next raft. Context stays only within one raft. An agent cannot clear its own context in every CLI, so design settles how it is cleared; one option is a cheap supervisor that runs each raft in a fresh CLI session. *STATE* (c0253)

### Blocked, and who unblocked it
When any ticket of a raft blocks, the raft is marked blocked (the reasons are in Escalation to the human, above) and the worker lets go of it. A blocked layer stops the layers above it, not the ones below. Resolving a block records who unblocked it, each time. *STATE* (c0250); who unblocked it *STATE* (c0263)

### The idea stage
z-ticket really challenges the idea, and the ticket keeps it all: the user's ask word for word and dated, every question asked and its answer in order, and a clean, fully formed idea written from them. A clean adversarial agent on an expensive model checks that the written idea matches what the user said, nothing dropped, added or bent, and its findings are answered before the user sees the idea. The user confirms the idea as it now stands, and the confirmation is recorded. Only a confirmed idea goes to z-design, which takes over as it is today: acceptance tests as code and a design, reviewed back and forth. *STATE* (c0260)

### Models per command and activity
`.models.toml` already gives each command a real model per CLI, and spend records the model *STATE* (c0117). What is planned is a real model per activity within a command, not a named level: z-ticket's sharpening of the idea and its review, for example, use different models. Expensive models run every final review: the idea review, the final design round, the final code round and the full-force review. Cheaper, faster models do the work on the way there, and the cheapest do the waiting. Nothing expensive orchestrates or waits, and spend shows the cost per activity. *STATE* (c0261)

### The full-force final review
Once per ticket, before its layer merges, a full-force adversarial review on an expensive model, in a fresh context, checks that the design covers the idea and that the implementation delivers the design. It is given a limited view: the original ask, the design and the implementation as given, and none of the design reviews, refutes, harvests, PR comments or worker notes on the way, so it judges the result on its merits. Its verdict says plainly whether the work stayed on course, with each gap named. When it did not, the ticket goes back to z-design (the design missed the idea) or its layer is rebuilt (the implementation missed the design), and the review runs again; a second off-course verdict blocks the ticket. *STATE* (c0262)

### Rank and lost work
A ticket or raft may carry a rank, and unset is the lowest. Equal or unset ranks fall back to the ticket number, so the order is always stable. Work that is in progress but lost, meaning its heartbeat (pushed to `main` every 5 minutes) went stale, comes before anything not yet started, whatever its rank and even if a person started it without updating the rank. An item that is blocked, or waits on undone work (`depends_on`), is skipped and keeps its rank. z-raft asks for a rank when it makes a raft, and unset is a valid answer; `./zn rank` can also unset a rank. A worker that takes over lost work does so as a normal claim, and the takeover is recorded. *STATE* (c0249); the heartbeat and lost work *STATE* (c0265)

### Provenance
A ticket records who had the idea (taken from git), who approved the design, who unblocked it, who confirmed the idea, who set the rank, who rafted it and which worker delivered each layer, and the board shows them. Design approval is an explicit human step before a ticket is prepared. *STATE* (c0263)

### The board app
The Omarchy board app shows tickets and rafts in the order Rank and lost work describes (lost work first, then rank with unset ranks last, the ticket number as the tiebreak), marks lost items, and reorders by drag and drop, which sets the rank through `./zn rank`. *STATE* (c0257)
TXT
IFS= read -r -d '' ROWS <<'TXT'
| the capture interview and idea review | c0260 | STATE |
| a real model assigned to each command and activity | c0261 | STATE |
| the full-force final review, limited view, redo | c0262 | STATE |
| ticket provenance: author, design approver, who unblocked | c0263 | STATE |
| work heartbeat, lost items first | c0265 | STATE |
| the Omarchy board app: rank order, drag and drop | c0257 | STATE |
| `agy`, `kimi` and `deepseek` as dispatch CLIs | c0175 | STATE |
TXT
IFS= read -r -d '' DIAGRAM <<'TXT'
  interview["idea interview, review, confirmation: c0260"] --> cap
  zwork["z-work, any CLI: c0253"] --> loop
  models["a real model per command and activity, expensive on every final review: c0261"] -.-> loop
  rev --> final["full-force final review, limited view: c0262"]
  final -. "off course: redo" .-> loop
  merge -. "raft merged or blocked: clear context, next raft: c0253" .-> loop
  lost["lost work first: heartbeat c0265, rank c0249"] -.-> stack
  prov["who had the idea, approved the design, unblocked it: c0263"] -.-> stack
TXT

INTENT="${INTENT%$'\n'}"; SECTIONS="${SECTIONS%$'\n'}"; ROWS="${ROWS%$'\n'}"; DIAGRAM="${DIAGRAM%$'\n'}"

# The tracker's state of an issue: done = exists, design: ready = designed, else captured; an id the tracker does not have
# (the capture branch not landed) is "missing" and fails.
real() {
	local path
	path="$(cd "$ROOT" && "$ROOT/zn" find "$1" 2>/dev/null | head -1)"; [[ -n $path ]] || { echo missing; return; }
	if [[ $path == */done/* ]]; then echo exists
	elif grep -q '^design: ready' "$ROOT/$path/$1.md" "$path/$1.md" 2>/dev/null; then echo designed
	else echo captured; fi
}
# stdin with each `*state* (cNNNN)` label's word replaced by STATE
norm() { sed -E 's/\*(exists|designed|captured)\* \((c[0-9]{4})\)/*STATE* (\2)/g'; }
# One `### ` sub-section (heading line included) of stdin, up to the next `##` or `###` heading
section() { awk -v t="### $1" '$0==t{on=1;print;next} /^##+ /{on=0} on'; }
# Every label on stdin is true: its word is the tracker's state of its issue
labels_true() {
	local bad=0 word id want
	while read -r word id; do
		[[ -n $id ]] || continue
		want="$(real "$id")"; [[ $word == "$want" ]] || { echo "$id: README says $word, tracker says $want"; bad=1; }
	done < <(grep -oE '\*(exists|designed|captured)\* \(c[0-9]{4}\)' | sed -E 's/^\*([a-z]+)\* \((c[0-9]{4})\)$/\1 \2/')
	return $bad
}
titles() { grep '^### ' <<<"$SECTIONS" | sed 's/^### //'; }

verbatim_intent() {
	local got
	got="$(awk '/^## Intent$/{on=1} /^## How it should work$/{on=0} on' "$README")"
	[[ "$got" == "$INTENT" ]] || { echo "the Intent section differs from the Design's text:"; diff <(printf '%s\n' "$INTENT") <(printf '%s\n' "$got"); return 1; }
}
# The How it should work section of the README (its heading up to the next `## `)
workflow() { awk '/^## How it should work$/{on=1;print;next} /^## /{on=0} on' "$README"; }
verbatim_sections() {
	local t bad=0 want got last=0 at roadmap
	roadmap="$(workflow | grep -n '^### Roadmap$' | head -1 | cut -d: -f1)"
	while IFS= read -r t; do
		want="$(section "$t" <<<"$SECTIONS")"; got="$(workflow | section "$t" | norm)"
		[[ -n $got && "$got" == "$want" ]] || { echo "sub-section '$t' differs from the Design's text, or is not in How it should work:"; diff <(printf '%s\n' "$want") <(printf '%s\n' "$got"); bad=1; continue; }
		at="$(workflow | grep -nxF -e "### $t" | head -1 | cut -d: -f1)"
		[[ -n $roadmap && $at -gt $last && $at -lt $roadmap ]] || { echo "sub-section '$t' is not in order, before ### Roadmap"; bad=1; }
		last=$at
	done < <(titles)
	return $bad
}
labels_in_sections() {
	local t
	while IFS= read -r t; do workflow | section "$t"; done < <(titles) | labels_true
}
# The Roadmap table: the lines of \`### Roadmap\` up to the next heading
roadmap() { workflow | awk '/^### Roadmap$/{on=1;next} /^##+ /{on=0} on'; }
roadmap_rows() {
	local id n row state key bad=0
	while read -r id; do
		n="$(roadmap | grep -cE "^\| .* \| $id \| (exists|designed|captured) \|$")"
		[[ $n == 1 ]] || { echo "$id: $n roadmap rows (one expected)"; bad=1; continue; }
		row="$(roadmap | grep -E "^\| .* \| $id \| (exists|designed|captured) \|$")"
		state="$(sed -E 's/^.* \| ([a-z]+) \|$/\1/' <<<"$row")"
		[[ $state == "$(real "$id")" ]] || { echo "$id: row says $state, tracker says $(real "$id")"; bad=1; }
		# a key word of the ticket's title, so a row can be another PR's own wording but not a placeholder
		case $id in c0260) key=interview;; c0261) key=model;; c0262) key='final review';; c0263) key=provenance;; c0265) key=heartbeat;; c0257) key=board;; c0175) key=deepseek;; *) key=;; esac
		grep -qiF -e "$key" <<<"$row" || { echo "$id: the row does not say '$key'"; bad=1; }
	done < <(grep -oE 'c[0-9]{4}' <<<"$ROWS")
	return $bad
}
diagram_lines() {
	local block bad=0 l
	block="$(awk '/^## How it should work$/{on=1} on&&/^```mermaid/{f=1;next} f&&/^```/{exit} f' "$README")"
	while IFS= read -r l; do grep -qxF -e "$l" <<<"$block" || { echo "the diagram lacks: $l"; bad=1; }; done <<<"$DIAGRAM"
	for l in c0253 c0260 c0261 c0262 c0263 c0265; do grep -qF -e "$l" <<<"$block" || { echo "the diagram does not name $l"; bad=1; }; done
	return $bad
}
# The ask, verbatim, in this issue's own document (the capture quotes every message; one sentence from each of five)
ask_quoted() {
	local doc s bad=0 d
	d="$(cd "$ROOT" && "$ROOT/zn" find c0264 2>/dev/null | head -1)"; doc="$ROOT/$d/c0264.md"
	for s in 'manually start any cli (kimi, agy, claude, grok, agent, deepseek) run a command, z-work.' \
		'We need a rank field that if unset is lowest rank and falls back to ticket number (always a stable sort order)' \
		'Also explicitly state that a worker clears itself and picks up the next raft whenever a raft is merged.' \
		'should be fed a limited view of the tickets so that it looks at it only on its merits as given' \
		'I want a model where a raft of multiple tickets is deliveered as a PR stack'; do
		grep -qF -e "$s" "$doc" || { echo "c0264.md lacks: $s"; bad=1; }
	done
	return $bad
}

check "AC1: '## Intent' is the first '##' section and '## How it should work' follows it at once" lune run tests/run -- "$A/intent-ac1.spec.luau"
check "AC2: the Intent has the three bold lead-ins, in order" lune run tests/run -- "$A/intent-ac2.spec.luau"
check "AC3: the Intent is a plain aim with no state label" lune run tests/run -- "$A/intent-ac3.spec.luau"
check "AC4: the Intent is the Design's text, word for word" verbatim_intent
check "AC5: each new sub-section of How it should work is the Design's text, word for word" verbatim_sections
check "AC6: every label in the new sub-sections is the tracker's state of its ticket" labels_in_sections
check "AC7: the roadmap has exactly one row for each of the seven tickets, with its true state" roadmap_rows
check "AC8: the workflow diagram gains the eight lines and names every new ticket" diagram_lines
check "AC9: this issue quotes the ask verbatim" ask_quoted
check "AC10: the specs that read the README still pass" lune run tests/run -- \
	tests/acceptance/c0259/readme.spec.luau tests/acceptance/c0115/readme.spec.luau tests/acceptance/c0115/docs.spec.luau \
	tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0117/docs.spec.luau tests/acceptance/c0183/docs.spec.luau \
	tests/acceptance/c0184/docs.spec.luau tests/acceptance/c0185/docs.spec.luau \
	tests/acceptance/c0082/audit.spec.luau tests/acceptance/c0115/layout.spec.luau tests/acceptance/c0120/graph-homes.spec.luau tests/acceptance/c0185/graph.spec.luau

check "AC11: no issue id has more than one Roadmap row" lune run tests/run -- "$A/roadmap-unique.spec.luau"
finish
