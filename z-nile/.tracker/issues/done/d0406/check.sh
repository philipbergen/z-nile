#!/usr/bin/env bash
# Acceptance checks for d0406. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0406 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0406"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# One run of the fast acceptance spec; each criterion reads its own cases from the output.
OUT="$(lune run tests/run -- "$A/idea-phases.spec.luau" 2>&1)"
# passes "<case name>": the run did not fail that case, and the file loaded
passes() {
	grep -q "passed," <<<"$OUT" || return 1
	! grep -q "could not load spec" <<<"$OUT" || return 1
	! grep -qF ":: $1" <<<"$OUT"
}
all() { local c; for c in "$@"; do passes "$c" || return 1; done; }

check "AC1: ledger lists idea and idea-challenge and still refuses any other phase" \
	all "ledger lists idea and idea-challenge, and still rejects any other phase"
check "AC2: metrics finishes on a tracker that holds idea rows" \
	all "metrics finishes on a tracker that holds idea rows"
check "AC3: metrics reports the idea rows under their own phases, in the raft row and as stages" \
	all "the phase table reports the idea rows' minutes and tokens under their own phases" \
	"the raft's row counts the idea minutes and tokens in its totals" \
	"metrics <issue> and metrics <raft> list the idea stages"
check "AC4: a phase nothing lists is printed after the listed ones" \
	all "a phase nothing lists is shown under its own name, after the listed ones"
check "AC5: a tracker with no idea row prints no idea line" \
	all "a tracker with no idea row prints no idea line in the phase table"
check "AC6: the rounds and lessons tables, the board and the summary readers finish on idea rows" \
	all "the rounds and lessons tables after the phase table are printed" \
	"the board is written from the same tracker" \
	"the readers a raft's spend summary uses return and total the idea rows"
# Two slow-tier specs, run once here on purpose, in one runner call: rounds.spec (4 s) and retired.spec (110 s
# alone, up to 290 s on a busy machine; measured 2026-11-17). They are the specs this defect turned red on main, the
# capture names both, and no gate runs them (lesson zz-test/check-sh-never-runs-the-slow-tier, c0302's note).
check "AC7: c0043/rounds.spec and c0116/retired.spec pass (2 to 5 min)" \
	lune run tests/run -- tests/acceptance/c0043/rounds.spec.luau tests/acceptance/c0116/retired.spec.luau

finish
