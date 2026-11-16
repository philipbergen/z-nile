#!/usr/bin/env bash
# Acceptance checks for c0195. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0195 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0195"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: every spelling of a branch copy is refused in a protected repository, which stays as it was, on every git here" \
  lune run tests/run -- "$A/copy.spec.luau"
check "AC2: every spelling of a branch rename is refused before git moves the branch's reflog, on every git here" \
  lune run tests/run -- "$A/rename.spec.luau"
check "AC3: a copy or rename aimed at the protected repository by -C, --git-dir or --work-tree is refused" \
  lune run tests/run -- "$A/away.spec.luau"
check "AC4: an alias or an external command is refused in a protected repository and runs in a fixture" \
  lune run tests/run -- "$A/others.spec.luau"
check "AC5: git's other commands run in a protected repository as before, and the ref guard's hook still refuses" \
  lune run tests/run -- "$A/reads.spec.luau"
check "AC6: the fence's git is first on the PATH once wherever the hooks are set, and off it under the jail" \
  lune run tests/run -- "$A/wiring.spec.luau"
check "AC7: the fence refuses without its git or another git on the PATH, and its git refuses without the real one" \
  lune run tests/run -- "$A/closed.spec.luau"
check "AC8: the zz-test and zz-arch skills, fence.sh's header and the gate scan's allowance state the fence's git" \
  lune run tests/run -- "$A/wording.spec.luau"
check "AC9: the fence's promoted specs (c0123's, as this issue overrides one) and the gate's guard scan still pass" \
  lune run tests/run -- tests/acceptance/c0131/accept.spec.luau tests/acceptance/c0131/refuse.spec.luau \
  tests/acceptance/c0114/guards.spec.luau tests/acceptance/c0058/fence.spec.luau tests/acceptance/c0127/reuse.spec.luau \
  tests/acceptance/c0120/homes.spec.luau tests/tooling/repo-fence.spec.luau tests/tooling/fence-inherited-env.spec.luau \
  tests/acceptance/c0123/launchers.spec.luau tests/acceptance/c0123/entries.spec.luau tests/acceptance/c0123/inherited-hooks.spec.luau \
  tests/tooling/fence-every-home.spec.luau

finish
