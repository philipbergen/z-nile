#!/usr/bin/env bash
# Acceptance checks for d0333. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0333 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0333"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# Each spec runs once (at the first criterion that names it, --run) and writes every passing case's name to a file;
# each criterion then checks its own cases. commit-land is a real-git fixture (16 to 24 s); post-finish is pure.
OUTDIR="$PWD/.cache/d0333-check"
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

check "AC1: layergit.isPostFinishPath takes the raft's own spend.md and no other new path" \
  cases post-finish --run "AC1: the post-finish rule takes the raft's own spend.md" 'AC1: the post-finish rule takes no other new path'
check "AC2: trace.staleReason keeps the table current when commits after the finish and after the table also rewrite the raft's spend.md, and still calls any other file stale" \
  cases post-finish "AC2: a trace commit that also rewrites the raft's spend.md leaves the table current" "AC2: review commits after the table that rewrite the raft's spend.md leave it current" 'AC2: any other file still makes the table stale, before and after it'
check "AC3: a finished raft that commits its trace table, final review and final refute with ./zn commit stays finished (./zn trace, and ./zn work next does not ask for another finish) and passes ./zn trace --check, each commit with its spend row" \
  cases commit-land --run 'sets up a one-ticket raft, finished' 'AC3: the Verification log committed with ./zn commit before the table leaves the layer finished' 'AC3: the trace table committed with ./zn commit leaves the layer finished and the table current' 'AC3: the final review and the final refute committed with ./zn commit leave the table current'
check "AC4: ./zn done lands that stack with the finish commit made before those commits, and their spend rows are in the landed ledger" \
  cases commit-land 'AC4: ./zn done lands that stack'
check "AC5: with the table and the final review committed, a ./zn commit of any other file still unfinishes the layer and makes the table stale, and ./zn done refuses because the layer is not finished" \
  cases commit-land 'AC5: a ./zn commit of any other file after the finish still unfinishes the layer'
check "AC6: the trace's fast spec stays green" lune run tests/run -- tests/tooling/trace.spec.luau
check "AC7: zz-execute Phase 5 commits the table and the final review files with ./zn commit and then verifies the check, and Phase 2B says a lower layer with any commit after its finish is finished again" lune run tests/run -- "$A/docs.spec.luau"

finish
