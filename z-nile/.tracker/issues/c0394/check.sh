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
# each criterion then checks its own cases. part-land, answers, whole and bound are real-git fixtures on c0248's layers (whole also runs on today's main),
# added and docs are pure.
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

check "AC1: \`added.luau\` places added issues in a raft's order, names the first waiting member and the member below it, and refuses an unknown \`waits:\` value and a \`before:\` that names an added issue or no member." \
  cases added --run 'a waits value other than approval is a problem' 'a before naming an added issue or no member is a problem, and a landed issue is not judged' 'place puts an added issue before the member it names, else last, lowest id first' "place leaves a raft with no added issue in stack.order's order" 'blocker is the first waiting member and names the member below it' 'an approved added issue is not a blocker'
check "AC2: \`./zn new issue … --raft <R> --wait --found <where> [--before]\` publishes an added issue and the raft's \`issues:\` line in one commit, commits nothing on the layer, prints the tell-the-user line, and refuses \`--wait\` without \`--raft\` or \`--found\` and \`--before\` off a layer of the raft." \
  cases part-land --run "new issue --raft --wait publishes the issue and the raft's issues: line in one commit, commits nothing on the layer, and says tell the user" '--wait needs --raft and --found, and --before needs a layer of the raft'
check "AC3: an issue added in front leaves the layer behind it its branch and pull request, and \`work next\`, \`list\` and the board, read on main, show it waiting and where it was found." \
  cases part-land 'stack prints T2, T1, T3 and T1 keeps its branch and pull request' 'work next, list and the board read on main show T2 waiting and where it was found'
check "AC4: \`./zn done <R>\` lands nothing while an issue waits in front of every complete layer, and names it." \
  cases part-land 'done lands nothing while T2 waits in front, and names T2'
check "AC5: after \`./zn approve <id>\`, the issue in front opens as the next free layer number, the parked layer is restacked on it and stays reviewed, and re-entering the worktree checks out the last member's layer." \
  cases part-land 'after approve, T2 opens in front as the next free layer number, T1 is restacked on it and stays reviewed' 'worktree re-entered checks out the layer of the last member with one'
check "AC6: \`./zn done <R>\` with no \`--through\` lands through the member below the first waiting one, leaves the raft and the waiting issue active on \`origin/main\` with \`./zn audit\` passing, and \`--through\` refuses an issue at or above a waiting member." \
  cases part-land 'done with no --through lands T2 and T1 and leaves the raft and T3 active on origin/main' 'audit is green after that landing' '--through refuses an issue at or above a waiting member'
check "AC7: \`./zn work next\` gives \`wait\` for a raft that only waits, with the approve and reject commands." \
  cases part-land 'work next says wait when only T3 is left'
check "AC8: after \`./zn approve <id>\`, the last added issue's layer starts on \`origin/main\` and \`done\` lands it and moves the raft to \`done/\`." \
  cases part-land "after approve, T3's layer starts on origin/main and done lands the raft"
check "AC9: \`./zn reject <id> --lesson <lesson id>\` removes a waiting issue in one published commit only with a \`not-worth-doing\` lesson, moves a raft with nothing left to \`done/\`, lets a layer behind a rejected issue land, and \`stop\` gives a waiting added issue back with the rest of its raft, still its member, which \`ready\` takes back." \
  cases part-land 'reject needs a not-worth-doing lesson, removes a waiting issue in one published commit, and moves a raft with nothing left to done' 'reject of an issue in front lets the layer behind it land' 'stop gives a waiting added issue back with the rest, still a member of its raft, and ready takes it back'
check "AC10: a raft with no added issue lands exactly as before." \
  cases whole --run 'a raft with no added issue lands whole'
check "AC11: a review answer may be \`dropped <lesson id>\` (medium or low) or \`added <id>\` (a high only in front of its layer or with the user's ruling), in code, final and design refutes, and a written \`deferred <id>\` is still accepted and called legacy." \
  cases answers --run 'dropped needs a not-worth-doing lesson and a medium or low finding' 'added needs an added issue of this raft' "a high added in front of its layer is accepted, and last is refused without the user's ruling" "a design refute's dropped and added answers are judged when the issue is prepared" 'a deferred answer is still accepted and called legacy'
check "AC12: \`./zn new issue … --with <id> --found <where>\` makes a bound issue in its issue's project that reaches prepared in the same prep with no idea challenge, rafts, folds, unfolds and recombines with its issue, and is not asked for an approval by \`ready\`." \
  cases bound --run 'new issue --with needs a preparing issue and --found, takes its project, and writes with, waits, found and idea: finding' "a bound issue goes from new to prepared in its issue's prep without an idea challenge" "raft-plan puts a bound issue in its issue's raft whatever its type" 'fold, unfold and recombine move an issue and its bound issue together' 'ready asks no approval of a waiting member'
check "AC13: zz-rules states the four ends of a finding, the threshold and the placing question once, no skill, AGENTS.md or README tells an agent to open a backlog issue for a finding, and zz-execute prescribes the Added comment and the report line." \
  cases docs --run 'zz-rules has Findings with the four ends, the 50-line threshold and the in-front-or-last question, and no Emergent issues section' 'no skill, AGENTS.md or README tells an agent to open a backlog issue for a finding or a lesson' 'zz-execute has the Added comment line and the report line, and no Follow-ups filed'
check "AC14: every skill's Lessons section and AGENTS.md say every lead writes a lesson straight into the lessons file." \
  cases docs "every skill's Lessons section has the Every lead bullet and no lesson-<slug> capture"
check "AC15: z-ticket and the idea challenger's prompt (for a z-nile issue that is not a finding) state that a z-nile ticket needs the user's ask or a second occurrence." \
  cases docs 'z-ticket states the z-nile ticket rule and the challenge prompt asks for it for z-nile only and not for a finding'
check "AC16: the usage text lists \`--wait\`, \`--before\`, \`--found\`, \`--with\` and \`reject\`." \
  cases docs 'usage lists --wait, --before, --found, --with and reject'

finish
