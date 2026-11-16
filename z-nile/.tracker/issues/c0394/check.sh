#!/usr/bin/env bash
# Acceptance checks for c0394. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0394 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0394"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# Each spec runs once (at the first criterion that names it, --run) and writes every passing case's name to a file;
# each criterion then checks its own cases. part-land is a real-git fixture (about 25 s), whole, answers and bound are
# small ones, added and docs are pure.
OUTDIR="$PWD/.cache/c0394-check"
cases() {
	local spec="$1" home rel out c
	shift
	home="$(pwd -P)"
	rel="${A#"$home"/}/$spec.spec.luau" # the runner takes the spec's path from the project home
	out="$OUTDIR/$spec.txt"
	if [[ ${1:-} == --run ]]; then
		shift
		mkdir -p "$OUTDIR" && : >"$out" # an empty record when no case passes: each criterion then names its case
		# the runner reads the project registry from the repository root
		(cd "$(git rev-parse --show-toplevel)" && lune run "$home/specs" -- run --project z-nile --out "$out" -- "$rel") || true
	fi
	[[ -f $out ]] || { echo "$spec.spec did not run"; return 1; }
	for c in "$@"; do
		grep -qxF "	$c" "$out" || { echo "did not pass: $c"; return 1; }
	done
}

check "AC1: \`added.luau\` places added issues in a raft's order and plans what lands, what blocks and what is above the blocker, and refuses an unknown \`waits:\` value and a \`before:\` that names no unlanded member." \
  cases added --run 'a waits value other than approval is a problem' 'a before naming a landed member or no member is a problem' 'place puts an added issue before the member it names, else last, lowest id first' "place leaves a raft with no added issue in stack.order's order" 'plan lands the finished members below the first waiting one' 'an approved added issue is not a blocker' 'plan names the first unfinished member below the blocker'
check "AC2: \`./zn new issue … --raft <R> --wait --found <where> [--before <id>]\` makes an added issue (\`waits:\`, \`found:\`, \`before:\`, in the raft's \`issues:\` line), prints the tell-the-user line, and refuses \`--wait\` without \`--raft\` or \`--found\` and a \`--before\` that names no unlanded member." \
  cases part-land --run 'new issue --raft --wait writes waits, found and before, joins issues: and says tell the user' '--wait needs --raft and --found, and --before needs an unlanded member'
check "AC3: an issue added in front leaves the layers above it their branches and pull requests, takes no layer while it waits, is left out of \`members\` with what is above it, and commits under its folder keep a layer finished." \
  cases part-land 'stack prints T2, T1, T3 and T1 keeps its branch and pull request' 'start opens no layer for a waiting member and work goes on above it' 'members omits the waiting issue and what is above it, --all prints every member' "a commit under a waiting member's folder keeps the layer finished"
check "AC4: \`./zn done <R>\` lands nothing while an issue waits in front of every finished layer, and names it and what is above it." \
  cases part-land 'done lands nothing while T2 waits in front, and names T2 and what is above it'
check "AC5: after \`./zn approve <id>\`, the added issue's layer takes the next free number on \`origin/main\`, and \`restack\` puts the layers above on it." \
  cases part-land 'after approve, T2 gets the next free layer number on origin/main and restack puts T1 on it'
check "AC6: \`./zn done <R>\` lands a part: the members below the waiting issue are done on \`origin/main\`, the raft and the waiting issue stay active there, the binding commit names what waits, and \`./zn audit\` passes." \
  cases part-land 'done lands the part: T2 and T1 done, the raft and T3 active on origin/main, Waiting: in the binding commit' 'audit is green after a part lands'
check "AC7: \`./zn work next\` gives \`wait\` for a raft that only waits, with the approve and reject commands." \
  cases part-land 'work next says wait when only T3 is left'
check "AC8: after \`./zn approve <id>\`, the last added issue's layer starts on \`origin/main\` and \`done\` lands it and moves the raft to \`done/\`." \
  cases part-land "after approve, T3's layer starts on origin/main and done lands the raft"
check "AC9: \`./zn reject <id> --lesson <lesson id>\` removes a waiting issue only with a \`not-worth-doing\` lesson and unblocks what is above it, \`done\` then closes a raft with nothing left, and \`stop\` refuses a raft with a landed member." \
  cases part-land 'reject removes a waiting issue, needs a not-worth-doing lesson, unblocks what is above it, and done closes the raft' 'stop refuses a raft with a landed member'
check "AC10: a raft with no added issue lands exactly as before." \
  cases whole --run 'a raft with no added issue lands whole'
check "AC11: a review answer may be \`dropped <lesson id>\` (medium or low) or \`added <id>\` (any severity) under their rules, and a written \`deferred <id>\` is still accepted and called legacy." \
  cases answers --run 'dropped needs a not-worth-doing lesson and a medium or low finding' 'added needs a waiting member of this raft and takes a high finding' 'a deferred answer is still accepted and called legacy'
check "AC12: \`./zn new issue … --with <id> --found <where>\` makes a bound issue that rafts, folds and unfolds with its issue and is not asked for an approval by \`ready\`." \
  cases bound --run 'new issue --with needs a preparing issue and --found, and writes with, waits and found' "raft-plan puts a bound issue in its issue's raft whatever its type" 'unfold moves an issue and its bound issue together' 'ready asks no approval of a waiting member'
check "AC13: zz-rules states the four ends of a finding, the threshold and the placing question once, and no skill, AGENTS.md or README tells an agent to open a backlog issue for a finding; zz-execute's report names the added issues." \
  cases docs --run 'zz-rules has Findings with the four ends, the 50-line threshold and the in-front-or-last question, and no Emergent issues section' 'no skill, AGENTS.md or README tells an agent to open a backlog issue for a finding or a lesson' "zz-execute's report has Added issues waiting for approval and no Follow-ups filed"
check "AC14: every skill's Lessons section and AGENTS.md say every lead writes a lesson straight into the lessons file." \
  cases docs "every skill's Lessons section has the Every lead bullet and no lesson-<slug> capture"
check "AC15: z-ticket and the idea challenger's prompt (for a z-nile issue only) state that a z-nile ticket needs the user's ask or a second occurrence." \
  cases docs 'z-ticket states the z-nile ticket rule and the challenge prompt asks for it for z-nile only'
check "AC16: the usage text lists \`--wait\`, \`--before\`, \`--found\`, \`--with\`, \`members --all\` and \`reject\`." \
  cases docs 'usage lists --wait, --before, --found, --with, members --all and reject'

finish
