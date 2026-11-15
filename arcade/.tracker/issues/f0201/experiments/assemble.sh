#!/usr/bin/env bash
# Assembles wallet.spec and receipts.spec from the shared stub engine and each spec's cases (prep only: the specs
# are self-contained files, since a sequestered spec requires only through aliases).
set -euo pipefail
cd "$(dirname "$0")/.."
{
	printf '%s\n' '--!strict' \
		'-- f0201 AC3: Wallet, run from its real source on a stub engine (in-memory DataStores whose calls can yield,' \
		'-- a MemoryStore pass map, players). The arrival claims the free start due, else a held play, once per join, in one' \
		"-- UpdateAsync whose transform's last call decides; a failed or slow claim plays; the portal's pass is taken on every" \
		'-- arrival and lets a buy play; TeleportData is never read. Revives are used once, counted for the run, and bounded' \
		'-- per player (one write at a time, none known held, USE_SECONDS); reads are bounded too (busy, READ_SECONDS,' \
		'-- WAIT_SECONDS) and keep nothing for a player who left.'
	cat experiments/stub-server.luau experiments/wallet-cases.luau
} >acceptance/wallet.spec.luau
{
	printf '%s\n' '--!strict' \
		'-- f0201 AC4: Receipts, run from its real source on the same stub engine. ProcessReceipt grants a known product of' \
		"-- any title once, into that title's live record by user id, wherever it is processed, answering PurchaseGranted only" \
		'-- after the write; an unknown product or a failed write answers NotProcessedYet. ask prompts Roblox in live mode,' \
		'-- opens the test screen in test mode, nothing in closed mode; a test confirm grants into the test store only for a' \
		'-- screen this server opened for that player. Fresh grants and closed screens are handed to the place.'
	cat experiments/stub-server.luau experiments/receipts-cases.luau
} >acceptance/receipts.spec.luau
