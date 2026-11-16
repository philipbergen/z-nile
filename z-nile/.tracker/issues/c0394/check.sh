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
# each criterion then checks its own cases. part-land is a real-git fixture (about 20 to 40 s), answers and bound are
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

check "AC1: \`added.luau\` splits a raft's members into landed, due and waiting, and refuses an unknown \`waits:\` value." \
  cases added --run 'a waits value other than approval is a problem' 'split keeps order: landed, due, waiting' 'an approved added issue is due'
check "AC2: \`./zn new issue … --raft <R> --wait\` makes an added issue (\`waits: approval\`, in the raft's \`issues:\` line), prints the tell-the-user line, and \`--wait\` without \`--raft\` is refused." \
  cases part-land --run 'new issue --raft --wait writes waits, joins issues: and says tell the user' '--wait without --raft is refused'
check "AC3: \`start\`, \`members\` and \`finish\` leave a waiting member out: no layer, no check run, and commits under its folder keep the layer finished." \
  cases part-land 'start skips a waiting member and names approve and reject' 'members omits a waiting member, --all prints it' "a commit under the waiting member's folder keeps the layer finished"
check "AC4: \`./zn done <R>\` lands a part: the due members are done on \`origin/main\`, the raft and the waiting member stay active there, the binding commit names what waits, \`./zn audit\` passes, and a raft with only a waiting member is refused." \
  cases part-land 'done lands the part: due members done, raft and waiting member active on origin/main, Waiting: in the binding commit' 'audit is green after a part lands' 'done with only a waiting member is refused'
check "AC5: \`./zn work next\` gives \`wait\` for a raft that only waits, with the approve and reject commands." \
  cases part-land 'work next says wait'
check "AC6: after \`./zn approve <id>\`, \`start\` opens the added issue's layer on \`origin/main\` and \`done\` lands it and moves the raft to \`done/\`." \
  cases part-land 'after approve, start opens the next layer on origin/main and done lands the raft'
check "AC7: \`./zn reject <id> --lesson <lesson id>\` removes a waiting issue only with a \`not-worth-doing\` lesson, \`done\` then closes the raft, and \`stop\` refuses a raft with a landed member." \
  cases part-land 'reject removes the issue, needs a not-worth-doing lesson, and done closes the raft' 'stop refuses a raft with a landed member'
check "AC8: a raft with no added issue lands exactly as before." \
  cases part-land 'a raft with no added issue lands whole'
check "AC9: a review answer may be \`dropped <lesson id>\` or \`added <id>\` under their rules, and a written \`deferred <id>\` is still accepted and called legacy." \
  cases answers --run 'dropped needs a not-worth-doing lesson and a medium or low finding' 'added needs a waiting member of this raft' 'a deferred answer is still accepted and called legacy'
check "AC10: \`./zn new issue … --with <id>\` makes a bound issue that rafts, folds and unfolds with its issue and is not asked for an approval by \`ready\`." \
  cases bound --run 'new issue --with needs a preparing issue and writes with and waits' "raft-plan puts a bound issue in its issue's raft whatever its type" 'unfold moves an issue and its bound issue together' 'ready asks no approval of a waiting member'
check "AC11: zz-rules states the four ends of a finding and the threshold once, and no skill, AGENTS.md or README tells an agent to open a backlog issue for a finding; zz-execute's report names the added issues." \
  cases docs --run 'zz-rules has Findings with the four ends and the 50-line threshold, and no Emergent issues section' 'no skill, AGENTS.md or README tells an agent to open a backlog issue for a finding or a lesson' "zz-execute's report has Added issues waiting for approval and no Follow-ups filed"
check "AC12: every skill's Lessons section and AGENTS.md say every lead writes a lesson straight into the lessons file." \
  cases docs "every skill's Lessons section has the Every lead bullet and no lesson-<slug> capture"
check "AC13: z-ticket and the idea challenger's prompt state that a z-nile ticket needs the user's ask or a second occurrence." \
  cases docs 'z-ticket states the z-nile ticket rule and the challenge prompt asks for it'
check "AC14: the usage text lists \`--wait\`, \`--with\`, \`members --all\` and \`reject\`." \
  cases docs 'usage lists --wait, --with, members --all and reject'

finish
