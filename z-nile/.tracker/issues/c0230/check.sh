#!/usr/bin/env bash
# Acceptance checks for c0230. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0230 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0230"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the budget module reads the limits and the measurer's CPU line, picks the files over budget and renders the report" lune run tests/run -- "$A/budget.spec.luau"
# The suite's half (runner-budget.spec) burns nothing: a stand-in `times` pins the measurer's sum. The real proof that a
# grandchild's CPU is counted (proof-cpu.luau) spins about 1 s of CPU, so it runs only while the sequestered folder
# exists (before `./zn done`), under a kernel cap, and is never promoted as a spec (lesson zz-test/specs-never-burn-real-resources).
check "AC2: a concurrent run reports the spec files over the per-file wall or CPU budget after slowest: and before its summary, and the outcome stands (the real CPU count proved once, before ./zn done)" \
	bash -c "lune run tests/run -- '$A/runner-budget.spec.luau' && { [ '$A' != '$HERE/acceptance' ] || { ulimit -t 60; '$ZN_ROOT/zn' run --time 120 -- lune run '$A/proof-cpu.luau'; }; }"
check "AC3: the zz-test skill's Speed section states the fast-tests rule and the report, and the lesson the report names exists" lune run tests/run -- "$A/docs.spec.luau"
check "AC4: every lesson still parses and has a source" "$ZN_ROOT/zn" lessons --check
# The lesson's wording is pinned once, before `./zn done`, never in the suite (lesson text is meant to change).
check "AC5: the zz-test lesson states the rule in the design's words, keeps both sources and has a body of at most 1,200 bytes (checked before ./zn done only)" \
	bash -c "[ '$A' != '$HERE/acceptance' ] || lune run '$A/lesson-words.luau'"

finish
