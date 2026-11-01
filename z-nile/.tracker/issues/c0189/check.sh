#!/usr/bin/env bash
# Acceptance checks for c0189. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0189 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0189"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the repository hook refuses a ref update to a commit under a fixture identity and nothing else, and fixtures never run it" \
	lune run tests/run -- "$A/repo-hook.spec.luau"
check "AC2: hooks.plan decides from the reference hook text, what is installed and the git configuration, and names every problem, its fix and whose copy it compared with" \
	lune run tests/run -- "$A/hooks-plan.spec.luau"
check "AC3: ./zn hooks installs origin/main's hook where every worktree shares it, never a checkout's unmerged edit and never over a hook it does not know, and --check only reads" \
	lune run tests/run -- "$A/hooks-command.spec.luau"
check "AC4: the gate checks the hook, setup.sh installs it, and the lists and rules that mention it agree" \
	lune run tests/run -- "$A/wiring.spec.luau"
check "AC5: the ref guard, the fence scan, setup.sh and the docs that pin the texts this change touches still pass" \
	lune run tests/run -- tests/tooling/repo-fence.spec.luau tests/acceptance/c0131/accept.spec.luau \
	tests/acceptance/c0131/refuse.spec.luau tests/acceptance/c0055/setup-run.spec.luau \
	tests/acceptance/c0115/docs.spec.luau tests/acceptance/c0116/docs.spec.luau tests/acceptance/c0172/merge.spec.luau

finish
