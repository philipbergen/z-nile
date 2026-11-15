#!/usr/bin/env bash
# Acceptance checks for c0245. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0245 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0245"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

# c0191's narrowed spec is pinned while this issue's acceptance is sequestered; after `./zn done` the pin has done its
# work and later changes to that file are their own items' (zz-test/narrowing-pins-the-whole-file)
narrowed() {
  [[ -d $HERE/acceptance ]] || return 0
  lune run "$A/narrowed.luau"
}

check "AC1: an absolute path under the checkout counts only for a registered home's runner or a TOOLING entry, by the file it reaches" lune run tests/run -- "$A/absolute.spec.luau"
check "AC2: a relative path counts by where it lands from the call's folder and its cds, a background call included, never by its suffix" lune run tests/run -- "$A/relative.spec.luau"
check "AC3: with no checkout, or a relative path and no folder, the path alone decides as before" lune run tests/run -- "$A/fallback.spec.luau"
check "AC4: a refused path that looks like the tooling says why it is not the gate's own" lune run tests/run -- "$A/refusal.spec.luau"
check "AC5: the hook reads absolute and .. paths by the file they reach, with its checkout's registry" lune run tests/run -- "$A/hook.spec.luau"
check "AC6: zz-test and zz-arch restate the rule by file, never by suffix" lune run tests/run -- "$A/docs.spec.luau"
check "AC7: c0191's promoted boundcmd.spec is exactly the reviewed narrowing" narrowed
check "AC8: the promoted seatbelt specs stay green: c0191's boundcmd and hooks, c0244's homes, the review fixes" lune run tests/run -- tests/acceptance/c0191/boundcmd.spec.luau tests/acceptance/c0191/hooks.spec.luau tests/acceptance/c0244/homes.spec.luau tests/tooling/bounded-review.spec.luau

finish
