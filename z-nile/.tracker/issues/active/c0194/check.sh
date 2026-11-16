#!/usr/bin/env bash
# Acceptance checks for c0194. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0194 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0194"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: z-nile/lib/tmp.luau makes trees only under .cache/.tmp (refusing links), keeps every ancestor .luaurc alias and Rokit tool out of them, sweeps and reports stale ones, jails unguarded-code runs and lists the old ones" \
	lune run tests/run -- "$A/tmp.spec.luau"
check "AC2: a plain mktemp in an agent session honours TMPDIR (z-nile/bin/mktemp), and the runner embeds the same text" \
	lune run tests/run -- "$A/shim.spec.luau"
# The live-jail case returns where the run is not jailed (Linux, an outer sandbox, a jailed clone: it must not turn the
# promoted gate red there); on macOS it must have run jailed, which it proves by a marker (as c0076's check does).
runner_cases() {
	rm -rf .cache/c0194-runner
	lune run tests/run -- "$A/runner.spec.luau" || return 1
	if [[ $(uname -s) == Darwin && ! -f .cache/c0194-runner/jailed-cases-ran ]]; then
		echo "the live-jail case did not run: run this check outside any other sandbox, so the specs are jailed"
		return 1
	fi
}
check "AC3: the runner's temp folder is a fresh pickman-run.* under .cache/.tmp, the jail closes the rest of it (on macOS the live-jail case ran), a temporary tree is not a fixture, an outer sandbox must close every .cache/.tmp, unowned run folders are cleared" runner_cases
check "AC4: par.sh, the gate, setup, remap and deploy-beta make no tree outside .cache/.tmp; the SessionStart hook and ./zn tmp work" \
	lune run tests/run -- "$A/callers.spec.luau"
check "AC5: AGENTS.md, SETUP.md and the skills name .cache/.tmp in the same words, Merging's clone is made, proved and removed by ./zn tmp, and unguarded-code runs go through ./zn tmp jail" \
	lune run tests/run -- "$A/docs.spec.luau"
check "AC6: the guards and the specs around them stay green (gate spec, fixture helper, cache paths, nested runners, par.sh, the gate's writers, merge rules, worktree, remap)" \
	lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/tooling/fence-leftovers.spec.luau tests/tooling/lock-start-ids.spec.luau \
	tests/tooling/migrate-odd.spec.luau tests/acceptance/c0060/fixture.spec.luau tests/acceptance/c0077/cache-paths.spec.luau \
	tests/acceptance/c0049/par-stages.spec.luau tests/acceptance/c0127/reuse.spec.luau tests/acceptance/c0172/merge.spec.luau \
	tests/acceptance/c0005/worktree.spec.luau tests/acceptance/c0052/new-spacing.spec.luau tests/acceptance/c0052/renumber.spec.luau \
	tests/acceptance/c0081/remap.spec.luau tests/acceptance/c0120/layout.spec.luau tests/acceptance/c0077/replace-file.spec.luau

finish
