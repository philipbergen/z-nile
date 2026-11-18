#!/usr/bin/env bash
# Acceptance checks for c0388. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0388 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0388"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# AC1 runs the promoted spec itself: c0042/cli is in the slow tier (z-nile/tests/slow.tsv), which no --affected or
# --full gate runs (lesson z-design/guards-name-slow-tier-specs); it takes about 14 s, which a check.sh may spend here
# because no other check runs it (zz-test's slow-tier rule, c0302 note).
check "AC1: c0042's cli spec passes on the real tracker, its three cases included" lune run tests/run -- tests/acceptance/c0042/cli.spec.luau
check "AC2: the folders c0042's cli spec counts come from every registered root, skip a closed issue and a missing folder, and refuse a missing registry" lune run tests/run -- "$A/roots.spec.luau"
# the convention for slow board specs (c0118): inputs.tsv names what the spec reads and watch.txt its sources; no gate
# reads inputs.tsv today (lib/context.luau:52), so this pins the convention, not a cache
check "AC3: the spec's input and watch lists name what it now reads (the registry, the closing and store modules, the helper)" bash -c '
	grep -qxF -e "tests/acceptance/c0042/cli.spec.luau	z-nile/projects.toml" tests/inputs.tsv &&
	for p in z-nile/engine/closing.luau z-nile/engine/store.luau z-nile/tests/acceptance/c0042/ondisk.luau z-nile/projects.toml; do
		grep -qxF -e "$p" tests/acceptance/c0042/watch.txt || { echo "watch.txt lacks $p"; exit 1; }
	done'

finish
