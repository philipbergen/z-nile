#!/usr/bin/env bash
# Acceptance checks for c0302. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0302 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0302"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# the published main AC1 compares against, printed outside `check` (a passing command's output is hidden): a swapped origin is review's to catch
echo "AC1 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"
check "AC1: each of the seven fixture specs is its merge base plus only the two c0302 lines after its origin removal" python3 "$A/narrow.py" "$ZN_ROOT"
# a one-time real-work proof, here and not in a promoted case: the seven are slow-tier (tests/slow.tsv), so no gate runs
# them, and they are what this issue changes. About 65 s (prep, 2026-11-14): two runs of the seven in a clone under $TMPDIR.
check "AC2: in a clone of this checkout, the seven fixture specs pass on the layer branch R9999/1/c9999 and on a plain branch" bash "$A/layer.sh"
check "AC3: every spec under z-nile/tests that clones, removes origin and runs start names its clone's branch main between that clone and the start, and the scan finds each wrong form" lune run tests/run -- "$A/fixtures.spec.luau"
check "AC4: layergit.mainTip still fails with 'no main branch' on a lone layer branch, and answers main's commit when there is a main" lune run tests/run -- "$A/maintip.spec.luau"

finish
