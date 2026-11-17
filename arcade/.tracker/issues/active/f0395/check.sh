#!/usr/bin/env bash
# Acceptance checks for f0395. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0395 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0395"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the test screen's lines: a play's price line strikes the struck price as rich text, <s>5 R\$</s> 1 R\$ SALE, built from the prices given; a revive's is Prices.revive, 1 R\$, nothing struck; every text escaped for rich text; Prices is one frozen table with the revive's price" lune run tests/run -- "$A/lines.spec.luau"
check "AC2: the test purchase screen renders every line label as rich text, showing each line exactly as the server sent it" lune run tests/run -- "$A/client.spec.luau"
check "AC3: the library's architecture names a revive's price in the Prices bullet and says the test screen's lines are rich text, a play's price struck" lune run tests/run -- "$A/docs.spec.luau"
check "AC4: PaidPlay stays an engine-free Logic feature with unit specs, and its unit specs pass" lune run tests/run -- tests/meta/architecture.spec.luau tests/unit/PaidPlay/paidplay.spec.luau
check "AC5: c0202 (Switch to arcade paid play) depends on this issue" bash -c 'd=$("$ZN_ROOT/zn" find c0202) && grep -Eq "^depends_on: \[(.*[ ,])?f0395[],]" "$d/c0202.md"'

finish
