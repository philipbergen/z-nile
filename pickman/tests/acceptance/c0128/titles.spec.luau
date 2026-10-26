--!strict
-- c0128 AC2: two promoted hiscore adapter specs are narrowed so they stop forbidding d0124's top-10 list of runs, and
-- nothing else changes. This file pins that no case is removed, renamed, added or moved; guards.spec pins what each
-- narrowed case still checks. Both read the files as text; running them is AC1.
local fs = require("@lune/fs")
local renamed = require("@tests/lib/renamed")
local t = require("@tests/lib/t")

local ROOT = "tests/" .. "acceptance/"
local F24 = ROOT .. renamed.id("f0024") .. "/adapter.spec.luau"
local F26 = ROOT .. renamed.id("f0026") .. "/adapters.spec.luau"

local function titles(path: string): { string }
	local out: { string } = {}
	for title in string.gmatch(fs.readFile(path), '%f[%w]it%(%s*"([^"]*)"') do
		table.insert(out, title)
	end
	return out
end

return t.spec("c0128 case titles", function(it)
	it("f0024 adapter keeps every case, in order, under its title", function()
		t.expect(titles(F24)).toEqual({
			"the feature is one init module and it does not touch the engine or the clock",
			"the adapter calls the pure drive, the modern budgets, and no environment prefix or dedupe",
			"two submits for one user id and run both drive, and the better one is stored",
			"the ordered write is drive's max: a higher value already stored stays",
			"a lower submit rewrites neither the row nor the ordered key",
			"stores are the shared names scoped by period, budgets are the modern request types",
			"each update is preceded by the read and write budgets of its own store",
			"a submit is pending from the call until its drive ends, also when the drive fails",
			"a page size of 10 that the store rejects is tried once at 50, cut to N, and the rank still comes",
			"no rank is heard when the board cannot be read, and the write still happens",
		})
	end)

	it("f0026 adapters keeps every case, in order, under its title", function()
		t.expect(titles(F26)).toEqual({
			"the place files do not gain a Board or Rank remote",
			"Starts never opens a store, the lobby Main boots Boards after it, and Boards only reads",
			"Boards creates Board under Remotes and ignores anything but all, day or week",
			"a failed read still answers once, with failed = true and the rows it had, or none",
			"a request that arrives while the read is under way does not read again, and each gets one answer",
			"during an outage a client asking every second costs three reads of the board in ten seconds",
			"an error anywhere in the read, opening the store included, is a failed read and the board is not wedged",
			"a companion row that cannot be read fails the read: no short board is answered as healthy or cached",
			"a waiter who left before the read returned gets no answer, and Boards keeps no per-player state",
			"one player asking all and then day in the same second gets both boards, healthy",
			"Boards opens the ordered and the companion store under their own names and the board's scope",
			"a page of 50 after the size-10 fallback is cut to the top N before any companion is read",
			"a healthy empty board is an answer, not a failure",
			"the lobby screen asks for all once at start and draws the answer, marking the rank it was sent",
			"failed answers in a row ask again after 1, 2 and 4 s, then stop, and a healthy answer starts over",
			"a tap starts the failure count over, so a failed answer after the retries stopped is retried",
			"a failed day or week answer asks again for that board",
			"a retry or a late answer for a board the player left neither asks nor draws",
			"a failed answer asks for all once more after READ_GAP, and a healthy one never does",
			"all, day and week are buttons of at least the touch size that ask for only their board",
			"the lobby screen requires only Lobby and Travel, the modules f0061's fake engine serves it",
			"without a Board remote the lobby asks nothing and keeps the empty panel",
			"FlowView keeps an empty FireServer and hears Rank without waiting for it",
			"Ranks creates Rank in code and sends a rank only to a player still in the game",
			"the game server starts Ranks before Sessions",
		})
	end)
end)
