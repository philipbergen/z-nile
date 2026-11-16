#!/usr/bin/env bash
# Acceptance checks for c0348. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0348 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0348"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# Each fixture spec runs once (at the first criterion that names it, --run) and writes every passing case's name to
# a file; each criterion then checks its own cases (d0333's pattern). Measured at prep, on the prototype:
# deliver-publish about 20 s, commit-land about 18 s, spend-command about 30 s. The last is slow-tier
# (z-nile/tests/slow.tsv), so no gate runs it: it is one of the two files this chore changes, and AC7 runs it once
# (lessons zz-test/check-sh-never-runs-the-slow-tier, the c0302 note, and z-design/guards-name-slow-tier-specs).
OUTDIR="$PWD/.cache/c0348-check"
# cases <name> <spec path, absolute or from the home> [--run] <case>...
cases() {
	local name="$1" spec="$2" home rel out c
	shift 2
	home="$(pwd -P)"
	rel="${spec#"$home"/}" # the runner takes the spec's path from the project home
	out="$OUTDIR/$name.txt"
	if [[ ${1:-} == --run ]]; then
		shift
		mkdir -p "$OUTDIR" && : >"$out" # an empty record when no case passes: each criterion then names its case
		# the runner reads the project registry from the repository root
		(cd "$(git rev-parse --show-toplevel)" && lune run "$home/specs" -- run --project z-nile --out "$out" -- "$rel") || true
	fi
	[[ -f $out ]] || { echo "$name did not run"; return 1; }
	for c in "$@"; do
		grep -qxF "	$c" "$out" || { echo "did not pass: $c"; return 1; }
	done
}
P="$A/deliver-publish.spec.luau"

check "AC1: ./zn spend --phase deliver for a done issue, or for a done raft over its done members, publishes to origin/main, as one commit, only the rows that call records, prints the published sha, and leaves the worktree with the same rows committed and clean" \
  cases publish "$P" --run 'sets up a done issue, a done raft of two, a backlog issue and a worktree' 'a deliver row for a done issue is published as one commit that only appends that row' "a done raft's deliver row is shared over its done members in one published commit"
check "AC2: a deliver row stays on the branch, and the command says so, for an item that is not done and for a branch that holds rows of the item that have not landed; capture, prep, design-review and --begin never publish" \
  cases publish "$P" 'a deliver row for an item that is not done stays on the branch, and the command says so' 'the other phases never publish, for a done item either, and say nothing about it' 'rows this branch has not landed keep the deliver row on the branch too, and the command says so'
check "AC3: a deliver publish that fails, and a checkout that lacks rows origin holds, exit non-zero and record nothing (no commit, no file, no row, the measure buffer byte for byte), and the next run records exactly one row; a local commit that fails after the publish warns, exits 0 and leaves the tree as it was, and the sync it advises brings the row" \
  cases publish "$P" 'a checkout that lacks rows origin holds records nothing and asks for a sync' 'a deliver publish that fails records nothing, and the next run records one row' 'a local commit that fails after the publish warns, leaves the tree as it was, and a sync brings the row'
check "AC4: the publisher takes spend.d/<writer>.tsv only for a done issue of a registered root, beside its document, and only as an append of rows that parse and hold a deliver row" \
  cases publish "$P" "the publisher's path rule takes a spend.d file only for a done issue of a registered root" "the publisher takes a done issue's spend.d file only as an append of rows"
check "AC5: in a fixture that lands a raft with ./zn done, ./zn spend <R-id> --phase deliver then leaves the row on the fixture's origin main with no push by hand" \
  cases land tests/acceptance/d0333/commit-land.spec.luau --run 'AC4: ./zn done lands that stack' 'c0348: after done, ./zn spend --phase deliver puts its row on origin/main with no push by hand'
check "AC6: zz-execute and zz-rules name that one route (after done, in the raft's worktree, published by the command), the direct-push rule lists the file, and the advice to record it before the merge is gone" \
  lune run tests/run -- "$A/docs.spec.luau"
# spend-command is slow-tier: this is its one run (about 30 s)
check "AC7: c0084's spend-command.spec and d0333's commit-land.spec are exactly the changed files (pinned whole), their owners' check.sh files still name them, and spend-command passes" \
  bash -c 'lune run tests/run -- "$1/overrides.spec.luau" && lune run tests/run -- tests/acceptance/c0084/spend-command.spec.luau' _ "$A"

finish
