#!/usr/bin/env bash
# Acceptance checks for f0453. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0453 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0453"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: a defect is shipped when a fixed id was done on or before its capture day, not counted when open, unrecorded and counted with no fixes:" \
  lune run tests/run -- tests/tooling/rework-shipped.spec.luau
check "AC2: ./zn metrics prints the shipped formula, the old all-defects line, the not-counted line and the no-fixed-ticket line" \
  lune run tests/run -- tests/tooling/rework-shipped.spec.luau
check "AC3: ./zn audit errors on an unknown fixes: id and ./zn new issue d --fixes writes the key" \
  lune run tests/run -- tests/tooling/rework-shipped.spec.luau
check "AC4: shipped: no beside a Ruled (user, ...) line drops a defect, and without the line is ignored and an audit error" \
  lune run tests/run -- tests/tooling/rework-shipped.spec.luau

finish
