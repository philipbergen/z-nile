#!/usr/bin/env bash
# Assembles wallet.spec and receipts.spec from the shared stub engine and each spec's cases (prep only: the specs
# are self-contained files, since a sequestered spec requires only through aliases).
set -euo pipefail
cd "$(dirname "$0")/.."
{
	printf '%s\n' '--!strict' \
		'-- f0201 AC3: Wallet, run from its real source on a stub engine (in-memory DataStores whose calls can yield,' \
		'-- a MemoryStore pass map, players, a clock). The arrival claims the free start due, else a held play, once per join,' \
		"-- in one UpdateAsync whose transform's last call decides, writing f0145's record shape; a failed or slow claim plays;" \
		"-- the portal's pass (per title, written only after a read that answered down) is taken on every arrival within" \
		'-- WAIT_SECONDS; join data is never read. Revives are used once and counted for the run (less a refund, dropped' \
		'-- KEEP_SECONDS after a leave), bounded per player and title; reads are per title, busy, cached, time-limited and' \
		'-- held down for RETRY_SECONDS after a failure. A test store that cannot be opened has a stand-in; a live one has' \
		'-- none. Calls for a player who left claim nothing.'
	cat experiments/stub-server.part experiments/wallet-cases.part
} >acceptance/wallet.spec.luau
{
	printf '%s\n' '--!strict' \
		'-- f0201 AC4: Receipts, run from its real source on the same stub engine. ProcessReceipt grants a known product of' \
		"-- any title once, into that title's live record by user id, wherever it is processed, answering PurchaseGranted only" \
		'-- after the write; an unknown product or a failed write answers NotProcessedYet. A grant, a test grant and a refund' \
		'-- refresh the record this server saw, so a purchase is usable at once. ask prompts Roblox in live mode, opens the' \
		'-- test screen in test mode, nothing in closed mode; a test confirm grants into the test store only for a screen this' \
		'-- server opened for that player. Fresh grants and closed screens are handed to the place, which hears one client' \
		'-- message and never reads join data.'
	cat experiments/stub-server.part experiments/receipts-cases.part
} >acceptance/receipts.spec.luau
