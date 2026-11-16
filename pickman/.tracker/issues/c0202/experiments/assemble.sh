#!/usr/bin/env bash
# Assembles c0202's server specs from the shared stub engine and each spec's cases (prep only: a sequestered spec
# requires only through aliases, so each is a self-contained file). PREP ONLY: it rewrites this issue's sequestered
# acceptance/*.spec.luau in place, so it is never run during execution (the specs are sequestered then).
set -euo pipefail
cd "$(dirname "$0")/.."
header() {
	printf '%s\n' '--!strict'
	printf -- '-- %s\n' "$@"
}
{
	header "c0202 AC1: Pickman's game place on the arcade library's paid play (Wallet, Receipts), run from the real" \
		"sources of both on a stub engine whose stores the portal's server can share. The arrival takes what the player" \
		"holds whoever sold it: the free start due, a play bought on the portal or in the lobby, or the library's pass" \
		"(pickman/<user id>); anything else is refused and sent back to LobbyPlaceId, kicked when that fails. A claim" \
		"that fails plays. The place installs the library's Receipts once."
	cat experiments/stub.part experiments/arrive.part experiments/arrival-cases.part
} >acceptance/arrival.spec.luau
{
	header "c0202 AC2: Pickman's continue offer on the library's revives (Wallet.useRevive, Wallet.refund, Receipts.ask)," \
		"on the same stub engine: a revive held is used at once; none held opens Pickman's revive product (Roblox's" \
		"screen live, the library's test screen in test mode) and holds the countdown; a receipt continues; a closed" \
		"screen releases; a closed server sells nothing; a decline or a leave during the write gives the revive back;" \
		"one write in flight; a revive bought within the library's USE_SECONDS of a use is used when the span ends."
	cat experiments/stub.part experiments/arrive.part experiments/offer.part experiments/offer-cases.part
} >acceptance/offer.spec.luau
{
	header "c0202 AC3: Pickman's lobby sells Pickman on the library until the portal replaces it: a free start due or a" \
		"play held goes (the arrival charges), none opens Pickman's play product, a grant starts the game at once, a read" \
		"that answers down goes and leaves the library's pass, which the game place's arrival takes; a press during a" \
		"read is dropped; a press while the test screen is open opens no second one; Receipts is installed once."
	cat experiments/stub.part experiments/lobby.part experiments/arrive.part experiments/lobby-cases.part
} >acceptance/lobby.spec.luau
{
	header "c0202 AC4: the stored records across the switch. f0145's build and the library share Pickman's stores" \
		"(PaidPlay, PaidPlayTest) and the record shape { free, plays, continues, receipts }: a record f0145 wrote is" \
		"used as it was, a receipt it granted is not granted again, its free hour holds, its test credits stay in test" \
		"mode, and every record the new build writes has exactly f0145's four fields."
	cat experiments/stub.part experiments/lobby.part experiments/arrive.part experiments/offer.part experiments/records-cases.part
} >acceptance/records.spec.luau
(cd "$(git rev-parse --show-toplevel)" && stylua "$OLDPWD"/acceptance/*.spec.luau) # the repository's stylua.toml
