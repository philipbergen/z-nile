#!/usr/bin/env bash
# Acceptance checks for c0407. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0407 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0407"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# AC1 runs the promoted spec itself (it is in the slow tier, z-nile/tests/slow.tsv, which no --affected or --full gate
# runs: lesson z-design/guards-name-slow-tier-specs). The dispatcher's publish broker is unset for it, as c0304's AC1
# does: a dispatched step would hand the fixture's pushes to that broker and fail the spec for the environment.
check "AC1: every case of c0084/commit-phase passes, the narrowed deliver case included" env -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN lune run tests/run -- tests/acceptance/c0084/commit-phase.spec.luau
echo "AC2 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"
check "AC2: c0084/commit-phase is its merge base with exactly the two reviewed c0407 hunks, byte for byte (done's output bound and its session line matched; the subject assertion expecting the plain subject plus the printed note), and a base that is not the stale form is refused" python3 "$A/narrow.py" "$ZN_ROOT"

finish
