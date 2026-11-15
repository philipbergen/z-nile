#!/usr/bin/env bash
# Acceptance checks for f0201. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/f0201 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/f0201"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: PaidPlay: one free start per rolling hour per title and player, else one held play, else buy with nothing changed; a receipt id grants once and the last 50 are kept; a refund is its own credit; a held revive is used once; records read defensively (f0145's continues kept); an arrival plays when charged or failed, a buy only with the pass" lune run tests/run -- "$A/paidplay.spec.luau"
check "AC2: the configuration: live only for exactly live with both product ids, closed for live with one missing, else test; an id two products share belongs to neither; a store per mode; the shipped catalog of four titles; the badge text table (5 R$ struck, 1 R$, SALE); the test screen's lines and keys" lune run tests/run -- "$A/config.spec.luau"
check "AC3: Wallet on a stub engine: the arrival's claim once per join in one UpdateAsync whose last call decides, failed or slow claims play, the pass taken on every arrival, TeleportData never trusted; revives used once, counted for the run and bounded per player; reads bounded (busy, cached, time-limited); an unopenable store throws nothing" lune run tests/run -- "$A/wallet.spec.luau"
check "AC4: Receipts on a stub engine: a receipt of any title granted once into its own live record by user id wherever processed, PurchaseGranted only after the write, NotProcessedYet otherwise; ask prompts in live, opens the test screen in test, nothing when closed; test confirms only for a screen this server opened; grants and closed screens handed to the place" lune run tests/run -- "$A/receipts.spec.luau"
check "AC5: the test purchase screen on a stub client: the server's lines with BUY and CANCEL, centred inside the safe insets; taps, Return, KeypadEnter or ButtonA buy and Backspace or ButtonB cancel, on the press; its keys bound above the place's only while open" lune run tests/run -- "$A/client.spec.luau"
check "AC6: in the built library place PaidPlay is a Logic leaf, Prices and TestPurchase shared modules, Wallet, Receipts and Catalog server-only; nothing shared requires a server module; the server adapters read no TeleportData and hear only the test screen's answer; architecture.md declares the feature" lune run tests/run -- "$A/place.spec.luau"
check "AC7: PaidPlay and its unit specs exist; Logic stays engine-free, every dependency is declared, and every feature has unit specs" bash -c 'test -f src/shared/Logic/PaidPlay/init.luau && test -d tests/unit/PaidPlay && lune run tests/run -- tests/meta/architecture.spec.luau'

finish
