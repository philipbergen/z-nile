#!/usr/bin/env bash
# Acceptance checks for c0374. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0374 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0374"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
# AC1 runs the proof script `acceptance/reads-homes.luau`, which cuts the promoted spec's last case into a clone under
# .cache (the whole promoted spec is in the slow tier and takes minutes; AC2 pins its other cases). It has no .spec.luau
# name, so `./zn done` promotes it without putting a repository clone and nested runs into every full gate (design review
# 001 F2; lesson zz-test/specs-never-burn-real-resources): it runs here only while the sequestered folder exists, and
# after `done` the live tree is held by the promoted slow-tier spec c0120/finished.spec.
if [[ -d $HERE/acceptance ]]; then
  check "AC1: the finished-check scan passes on the repository, reads a bare ./zn inside single quotes as text (a helper's argument, a multi-line bash -c script), and still reports an unquoted path, a folder path in single quotes and unbalanced quotes, while a path missing before the move stays allowed" lune run tests/run -- "$HERE/acceptance/reads-homes.luau"
else
  check "AC1: (after done) the proof ran at finish; the promoted slow-tier spec c0120/finished.spec holds the live tree, and z-nile/tests/acceptance/c0374/reads-homes.luau is kept beside it" test -f "$A/reads-homes.luau"
fi
echo "AC2 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"
check "AC2: c0120/finished.spec is its merge base with exactly the two reviewed c0374 hunks, byte for byte (the singleQuoted helper and the last case's loop), and a base that is not the stale form is refused" python3 "$A/narrow.py" "$ZN_ROOT"

finish
