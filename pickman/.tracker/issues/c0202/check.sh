#!/usr/bin/env bash
# Acceptance checks for c0202. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0202 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0202"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the game place takes the arcade's entitlement on arrival: the free start due, a play bought on the portal or in the lobby, or the library's pass (pickman/<user id>) plays at once; anything else is refused and sent back to LobbyPlaceId (kicked when that fails); a failed claim plays; the place installs the library's Receipts once" lune run tests/run -- "$A/arrival.spec.luau"
check "AC2: the continue offer on the library's revives: a revive held is used at once; none held opens Pickman's revive product and holds the countdown; a receipt continues; a closed screen releases; a closed server sells nothing; a decline or leave during the write gives the revive back; one write in flight; a revive bought within USE_SECONDS of a use is used when the span ends" lune run tests/run -- "$A/offer.spec.luau"
check "AC3: the lobby sells Pickman on the library: a free start or a held play goes, none opens Pickman's play product, a grant starts at once, a read that answers down goes with the library's pass that the arrival takes, a press during a read is dropped, a press while the test screen is open opens nothing more, Receipts installed once" lune run tests/run -- "$A/lobby.spec.luau"
check "AC4: the stored records across the switch: f0145's records, receipts, free hour and test credits are the library's as they were, and every record written has exactly f0145's four fields" lune run tests/run -- "$A/records.spec.luau"
check "AC5: the screens say what they said, on the library's Prices and status: the lobby's line and the sale price, the offer's price line from the revives held, the offer's keys, its buttons inert under the library's open test screen, PayView's rich-text line, and both views boot the library's test screen" lune run tests/run -- "$A/clients.spec.luau"
check "AC6: no pickman-only copy: both places map the library, Pay, Purchases and TestPurchase are gone and nothing in pickman's src names them or sets ProcessReceipt, the servers wire Wallet and Receipts, the clients boot the library's screen, and the documents say so" lune run tests/run -- "$A/place.spec.luau"
check "AC7: f0145's and f0186's promoted specs, as this issue overrides them, pass" bash -c 'lune run tests/run -- tests/acceptance/f0145/*.spec.luau tests/acceptance/f0186/*.spec.luau'
check "AC8: Logic stays engine-free, every dependency is declared, and every feature has unit specs" lune run tests/run -- tests/meta/architecture.spec.luau

finish
