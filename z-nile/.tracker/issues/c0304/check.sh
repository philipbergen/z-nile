#!/usr/bin/env bash
# Acceptance checks for c0304. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0304 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0304"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# AC1 runs the promoted spec itself (it is in the slow tier, z-nile/tests/slow.tsv, which no --affected or --full gate
# runs: lesson z-design/guards-name-slow-tier-specs), and c0060/retrofit, which reads its text for raw git and which
# the selector does not pick for it (design review 001 F3). The dispatcher's publish broker is unset for it: inside a
# dispatched step the spec's fixture `start` would hand its push to that broker and the squash-merge case would fail
# for the environment, not the spec (c0304 E1; d0298 makes spec runs drop that environment, after which this is a no-op).
check "AC1: every case of c0045/workstreams passes, the two narrowed ones included, and c0060/retrofit still finds no raw git in it" env -u ZN_PUBLISH_BROKER -u ZN_PUBLISH_TOKEN lune run tests/run -- tests/acceptance/c0045/workstreams.spec.luau tests/acceptance/c0060/retrofit.spec.luau
echo "AC2 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"
check "AC2: c0045/workstreams is its merge base with exactly the three reviewed c0304 hunks, byte for byte (the raft-tip branch and both --from lines in case 1, the push in case 2), and a base that is not the stale form is refused" python3 "$A/narrow.py" "$ZN_ROOT"

finish
