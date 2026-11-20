#!/usr/bin/env bash
# Acceptance checks for d0331. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0331 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0331"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# layer-one, done-moved, done-push, restack-push and on-landed drive real git in fixtures under .cache and their cases build on
# each other, so each runs once (at the first criterion that names it, --run) and writes every passing case's name to
# a file; each criterion then checks its own cases. retry and docs are pure and take under a second.
OUTDIR="$PWD/.cache/d0331-check"
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
check "AC1: ./zn finish on layer 1 succeeds after origin/main gained a commit, as one finish commit on the commit the layer was cut from, with only the layer's own files" \
  cases layer-one --run 'AC1: finish accepts layer 1 after main gained a commit, as one commit on the fork, with only its own files'
check "AC2: after main moved, ./zn stack shows layer 1 finished, ./zn work next offers neither a restack nor a second finish, and ./zn start opens layer 2" \
  cases layer-one 'AC2: stack and work next call the layer finished after main moved, and start opens layer 2'
check "AC3: ./zn finish on layer 2 still refuses a layer off the layer below, and ./zn restack still moves the stack onto main's newest commit" \
  cases layer-one "AC3: a layer above still has to contain the tip of the layer below, and restack still moves the stack onto main's tip"
check "AC4: with every layer finished and main moved again, ./zn work next goes on to the code review" \
  cases layer-one 'AC4: with every layer finished, work next goes on to the review after main moved, never to a restack or a finish'
check "AC5: ./zn trace and ./zn done accept a finished stack behind origin/main, and done lands it on main's newest commit with no restack" \
  cases layer-one "AC5: trace and done accept the stack after main moved again, and done lands it on main's tip with no restack"
# AC6 and AC7 are also a pure decision (retry.spec); the two retry.spec cases run with AC6
ac6() {
	local ok=0
	cases done-moved --run 'AC6: main gains a commit during the gate, and done merges onto the new tip, gates again and lands by itself' || ok=1
	lune run tests/run -- "$A/retry.spec.luau" || ok=1
	return $ok
}
check "AC6: when main gains a commit during done's gate, done merges onto the new tip, gates again and lands by itself with one binding commit that holds both gates' cost rows" ac6
check "AC7: done stops after nine attempts lost to a moving main, rolled back and asking for done again, and does not try again a push rejected for another reason, on the first attempt or a later one" \
  cases done-moved 'AC7: main gains a commit during every gate, and done stops after nine attempts, rolled back, asking for done again' \
  'AC7: a push origin rejects while main stands still is not tried again: one gate, the push refusal, the base put back' \
  'AC7: main moves once and origin then rejects the push for another reason: two gates, then the push refusal, not nine'
check "AC8: a red gate on the merged tree and a merge conflict with main each refuse naming ./zn restack and leave the layer as it was" \
  cases done-moved 'AC8: a red gate on the merged tree and a merge conflict both refuse naming ./zn restack, and leave the layer as it was'
check "AC9: a restack whose push of one layer is rejected names that layer and every layer above it as not pushed, leaves the local layer as origin has it, returns to its branch, and the next restack repairs the remote stack" \
  cases restack-push --run 'AC9: the rejected layer is named as not pushed, the command fails, and the worktree is back on its branch' \
  'AC9: the next restack puts layer 3 on layer 2 on layer 1 on origin, each still one finish commit'
check "AC10: zz-execute's Phase 5, zz-rules' Items and zz-review's final mode say a moved main needs no restack and when a restack is needed" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC11: the real tree audits and lessons-checks clean, and the fast specs of the stack, the trace, work and done stay green" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- tests/tooling/trace.spec.luau tests/tooling/stack.spec.luau tests/tooling/work.spec.luau tests/acceptance/c0239/done.spec.luau'
check "AC12: a push of the binding commit that reached origin and reported failure has landed: no second attempt, the pull requests left on main" \
  cases done-push --run 'AC12: a push that reached origin and reported failure has landed: one gate, one bind, the pull request left on main'
check "AC13: when main moved and a pull request base cannot be put back, done stops at once and names the command that puts it back" \
  cases done-push 'AC13: main moved and the pull request base cannot be put back: done stops at once, naming the command that puts it back'
# The slow-tier specs that drive finish, restack, trace and done directly, by name (the gate, finish and a tooling
# merge all leave the slow tier out): about 160 s by tests/slow.tsv. A one-time proof for this change. They clone the
# checkout, so on a layer branch they need c0302 (depends_on). The three lifecycle specs of the Regression guard
# (c0001, c0067, c0120/finished: about 565 s) run once in Implementation step 9, not here.
check "AC14: the slow-tier specs of the stack, the trace and done stay green" \
  lune run tests/run -- --slow tests/tooling/stack-land.spec.luau tests/tooling/stack-fix.spec.luau tests/tooling/trace-land.spec.luau tests/acceptance/c0074/done-gate.spec.luau tests/acceptance/c0008/done-order.spec.luau
check "AC15: a raft readied --on another keeps f0399's rule for its layer 1: ready --on accepts a base whose finished layer 1 main moved past; a restack stopped at layer 1 after rebuilding the base leaves finish refusing; after the base raft lands, finish, trace and done (here and in another clone) refuse a layer 1 still on an older base commit naming ./zn restack; restack leaves only the layer's own commit, judged against its fork" \
  cases on-landed --run 'AC15: ready --on accepts a base raft whose finished layer 1 main moved past' \
  'AC15: before the raft it is built on lands, a restack stopped at layer 1 after rebuilding the base leaves that layer judged against the new base: finish refuses naming ./zn restack' \
  'AC15: after the raft it is built on lands, finish, trace and done refuse a layer 1 still on an older base commit, naming ./zn restack, and leave it as it was' \
  'AC15: restack moves that layer onto main as its own one commit, and then it is judged against its fork: main moves again and done lands it with no second restack'

finish
