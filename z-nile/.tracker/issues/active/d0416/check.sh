#!/usr/bin/env bash
# Acceptance checks for d0416. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/d0416 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/d0416"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
echo "AC1 base: $(git -C "$ZN_ROOT" ls-remote --get-url origin) refs/heads/main"
check "AC1: c0117's control-cli spec is its merge base with origin's main with exactly the three reviewed hunks, byte for byte" \
  python3 "$A/narrow.py" "$ZN_ROOT"
check "AC2: c0117's control-cli spec passes, its quiet-reviewer case included" \
  lune run tests/run -- --slow tests/acceptance/c0117/control-cli.spec.luau
check "AC3: a second design review is refused before any reviewer starts, from a real author step too, and a first nested review starts" \
  lune run tests/run -- "$A/nested-second-review.spec.luau"
check "AC4: d0415's two specs pass" \
  lune run tests/run -- tests/acceptance/d0415/dispatch.spec.luau tests/acceptance/d0415/filing.spec.luau
check "AC5: dispatch-cli and dispatch-guards, the other slow specs that dispatch reviews, pass, and no other spec reads control-cli's text" \
  bash -c '[ "$(grep -rlF --exclude-dir=d0416 "c0117/control-cli" tests | sort | tr "\n" " ")" = "tests/slow.tsv " ] &&
    lune run tests/run -- --slow tests/acceptance/c0117/dispatch-cli.spec.luau tests/tooling/dispatch-guards.spec.luau'

finish
