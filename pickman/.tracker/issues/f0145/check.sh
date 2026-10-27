#!/usr/bin/env bash
# Acceptance checks for f0145. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0145 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0145"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: Pay: one free start per rolling hour, then a held play, else buy; a receipt granted once; continues held and used once; live only for exactly live" lune run tests/run -- "$A/pay.spec.luau"
check "AC2: the continue offer: switched on per run, the last life opens it for OFFER_TICKS steps, held while a purchase screen is open, a decline ends it, a continue gives three new lives keeping the score, level and pellets; lives lost carried to the game over" lune run tests/run -- "$A/offer.spec.luau"
check "AC3: a run's lives spent reach its submission, the stored row and the rows read back, and the lobby's panel shows them; rows without them show none" lune run tests/run -- "$A/lives.spec.luau"
check "AC4: the offer's overlay (CONTINUE?, three new lives, the seconds left, the buttons), the price under it, and the lobby's line under START GAME" lune run tests/run -- "$A/views.spec.luau"
check "AC5: the paid-play adapters on a stub engine: receipts granted once, the lobby's gate and purchase screens, the start charged on arrival, the continue offer's purchases, holds and declines" lune run tests/run -- "$A/adapters.spec.luau"
check "AC6: the places boot the adapters, no client requires Purchases, the remote lists stay, and the documents state the paid play" lune run tests/run -- "$A/place.spec.luau"
check "AC7: d0124's top-10 list of runs carries each run's lives spent (once d0124 has landed)" lune run tests/run -- "$A/top.spec.luau"
check "AC8: Logic stays engine-free, every dependency is declared, and every feature has unit specs" lune run tests/run -- tests/meta/architecture.spec.luau

finish
