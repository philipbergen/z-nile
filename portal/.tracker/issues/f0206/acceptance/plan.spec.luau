--!strict
-- f0206 AC3: the server's read policy (Board.plan, pure). An ask may make the arcade's Boards read its stores only as
-- a refresh: REFRESH after the board's last one (or never read, or a clock that went back), with a token of the read
-- allowance (RATE a minute per player, at most BURST) and the engine's request budget holding COST above RESERVE. While
-- the last refresh is inside the arcade's cache time (ttl - MARGIN) and its answer did not fail, an ask is forwarded:
-- the arcade answers from its cache or the read under way. A forward of the all-time board that would read the
-- player's best needs one standard read above RESERVE and waits BEST_GAP. Every other ask the server answers from the
-- rows it holds. Over ten minutes of asks on every board every second, the reads stay inside the allowance and the
-- engine's per-server budget.
local Board = require("@logic/Board")
local t = require("@tests/lib/t")

local TTL = 15 -- the arcade's Hiscores.CACHE_TTL
local PLENTY: Board.Budget = { standard = 1000, sorted = 1000 }
local FULL: Board.Bucket = { tokens = 4, at = 0 }

local function snap(at: number?, failed: boolean?): Board.Snap
	return { at = at, failed = failed == true, known = at ~= nil, rows = {} }
end

local function ask(over: { [string]: any }): Board.Ask
	local a: { [string]: any } = {
		snap = nil,
		last = nil,
		all = false,
		bucket = FULL,
		budget = PLENTY,
		players = 1,
		now = 0,
		ttl = TTL,
	}
	for k, v in over do
		a[k] = v
	end
	return a :: any
end

return t.spec("f0206 plan", function(it)
	it("its numbers", function()
		t.expect(Board.REFRESH).toBe(30)
		t.expect(Board.MARGIN).toBe(2)
		t.expect(Board.BEST_GAP).toBe(60)
		t.expect(Board.RATE).toBe(1.5)
		t.expect(Board.BURST).toBe(4)
		t.expect(Board.COST.standard).toBe(12)
		t.expect(Board.COST.sorted).toBe(1)
		t.expect(Board.RESERVE.standard).toBe(20)
		t.expect(Board.RESERVE.sorted).toBe(2)
		t.expect(Board.REFRESH >= TTL).toBe(true)
	end)

	it("the first ask of a board is a refresh, and takes one token", function()
		local p = Board.plan(ask({ snap = nil }))
		t.expect(p.act).toBe("refresh")
		t.expect(p.bucket.tokens).toBeNear(3, 1e-9)
		t.expect(Board.plan(ask({ snap = snap(nil) })).act).toBe("refresh")
	end)

	it("inside the arcade's cache time an ask is forwarded and takes no token", function()
		for _, dt in { 0, 1, 12 } do
			local p = Board.plan(ask({ snap = snap(100), now = 100 + dt }))
			t.expect(p.act).toBe("forward")
			t.expect(p.bucket.tokens).toBeNear(4, 1e-9)
			t.expect(p.best).toBe(false)
		end
	end)

	it("the forward window ends MARGIN short of the arcade's cache time", function()
		t.expect(Board.plan(ask({ snap = snap(100), now = 112 })).act).toBe("forward")
		t.expect(Board.plan(ask({ snap = snap(100), now = 113 })).act).toBe("answer")
		t.expect(Board.plan(ask({ snap = snap(100), now = 113, ttl = 16 })).act).toBe("forward")
	end)

	it(
		"after the window and before REFRESH the server answers from its rows; at REFRESH it refreshes",
		function()
			t.expect(Board.plan(ask({ snap = snap(100), now = 113 })).act).toBe("answer")
			t.expect(Board.plan(ask({ snap = snap(100), now = 129 })).act).toBe("answer")
			t.expect(Board.plan(ask({ snap = snap(100), now = 130 })).act).toBe("refresh")
		end
	)

	it("a failed answer closes the window until the next refresh", function()
		t.expect(Board.plan(ask({ snap = snap(100, true), now = 101 })).act).toBe("answer")
		t.expect(Board.plan(ask({ snap = snap(100, true), now = 129 })).act).toBe("answer")
		t.expect(Board.plan(ask({ snap = snap(100, true), now = 130 })).act).toBe("refresh")
	end)

	it(
		"a clock that went back refreshes; a time that is not finite answers and leaves the allowance",
		function()
			t.expect(Board.plan(ask({ snap = snap(100), now = 90 })).act).toBe("refresh")
			local bucket: Board.Bucket = { tokens = 2, at = 50 }
			for _, bad in { 0 / 0, math.huge, -math.huge } do
				local p = Board.plan(ask({ snap = nil, now = bad, bucket = bucket }))
				t.expect(p.act).toBe("answer")
				t.expect(p.bucket).toBe(bucket)
			end
		end
	)

	it("BURST refreshes at once, then none until the allowance refills", function()
		local bucket: Board.Bucket = { tokens = 0, at = nil }
		local acts = {}
		for _ = 1, 5 do
			local p = Board.plan(ask({ snap = nil, bucket = bucket, now = 0 }))
			bucket = p.bucket
			table.insert(acts, p.act)
		end
		t.expect(table.concat(acts, " ")).toBe("refresh refresh refresh refresh answer")
	end)

	it("a board with rows refreshes only while KEEP more tokens are left for a board with none", function()
		t.expect(Board.KEEP).toBe(1)
		local one: Board.Bucket = { tokens = 1, at = 0 }
		local known: Board.Snap = { at = 100, failed = false, known = true, rows = {} }
		t.expect(Board.plan(ask({ snap = known, now = 130, bucket = { tokens = 1.9, at = 130 } })).act)
			.toBe("answer")
		t.expect(Board.plan(ask({ snap = known, now = 130, bucket = { tokens = 2, at = 130 } })).act)
			.toBe("refresh")
		t.expect(Board.plan(ask({ snap = nil, now = 0, bucket = one })).act).toBe("refresh")
		local unknown: Board.Snap = { at = 100, failed = false, known = false, rows = {} }
		t.expect(Board.plan(ask({ snap = unknown, now = 130, bucket = { tokens = 1, at = 130 } })).act)
			.toBe("refresh")
	end)

	it("the allowance refills RATE a minute per player, at least one, up to BURST", function()
		local empty: Board.Bucket = { tokens = 0, at = 0 }
		t.expect(Board.fill(empty, 40, 1).tokens).toBeNear(1, 1e-9)
		t.expect(Board.fill(empty, 39, 1).tokens < 1).toBe(true)
		t.expect(Board.fill(empty, 10, 4).tokens).toBeNear(1, 1e-9)
		t.expect(Board.fill(empty, 40, 0).tokens).toBeNear(1, 1e-9)
		t.expect(Board.fill(empty, 100000, 50).tokens).toBe(Board.BURST)
		t.expect(Board.fill({ tokens = 0, at = nil }, 7, 1).tokens).toBe(Board.BURST)
		local back = Board.fill({ tokens = 1.5, at = 100 }, 50, 3)
		t.expect(back.tokens).toBe(1.5)
		t.expect(back.at).toBe(50)
		t.expect(Board.plan(ask({ snap = nil, bucket = { tokens = 0, at = 0 }, now = 39 })).act)
			.toBe("answer")
		t.expect(Board.plan(ask({ snap = nil, bucket = { tokens = 0, at = 0 }, now = 40 })).act)
			.toBe("refresh")
	end)

	it("a refresh needs the engine's budget to hold COST above RESERVE, of both kinds", function()
		local atSorted = { standard = 1000, sorted = Board.RESERVE.sorted + Board.COST.sorted }
		local belowSorted = { standard = 1000, sorted = Board.RESERVE.sorted + Board.COST.sorted - 1 }
		local atStandard = { standard = Board.RESERVE.standard + Board.COST.standard, sorted = 1000 }
		local belowStandard = { standard = Board.RESERVE.standard + Board.COST.standard - 1, sorted = 1000 }
		t.expect(Board.plan(ask({ budget = atSorted })).act).toBe("refresh")
		t.expect(Board.plan(ask({ budget = belowSorted })).act).toBe("answer")
		t.expect(Board.plan(ask({ budget = atStandard })).act).toBe("refresh")
		t.expect(Board.plan(ask({ budget = belowStandard })).act).toBe("answer")
		local p = Board.plan(ask({ budget = belowSorted }))
		t.expect(p.bucket.tokens).toBeNear(4, 1e-9)
	end)

	it("an all-time ask the arcade would answer with a fresh read of the player's best is marked", function()
		local p = Board.plan(ask({ all = true, snap = snap(100), now = 101, last = nil }))
		t.expect(p.act).toBe("forward")
		t.expect(p.best).toBe(true)
		local again = Board.plan(ask({ all = true, snap = snap(100), now = 101, last = 41 }))
		t.expect(again.act).toBe("forward")
		t.expect(again.best).toBe(true)
	end)

	it("an all-time forward while the arcade still holds the player's best reads none", function()
		local p = Board.plan(ask({ all = true, snap = snap(100), now = 105, last = 95 }))
		t.expect(p.act).toBe("forward")
		t.expect(p.best).toBe(false)
	end)

	it(
		"between the arcade's hold and BEST_GAP an all-time ask is answered from the rows, not forwarded",
		function()
			t.expect(Board.bestRead(95, 108, TTL)).toBe("hold")
			t.expect(Board.bestRead(95, 107, TTL)).toBe("fresh")
			t.expect(Board.bestRead(95, 155, TTL)).toBe("read")
			t.expect(Board.bestRead(95, 154, TTL)).toBe("hold")
			t.expect(Board.bestRead(nil, 0, TTL)).toBe("read")
			t.expect(Board.bestRead(95, 90, TTL)).toBe("read")
			local p = Board.plan(ask({ all = true, snap = snap(100), now = 110, last = 95 }))
			t.expect(p.act).toBe("answer")
		end
	)

	it("a forward that reads the best needs one standard read above RESERVE", function()
		local tight = { standard = Board.RESERVE.standard, sorted = 1000 }
		t.expect(Board.plan(ask({ all = true, snap = snap(100), now = 101, budget = tight })).act)
			.toBe("answer")
		local enough = { standard = Board.RESERVE.standard + 1, sorted = 1000 }
		t.expect(Board.plan(ask({ all = true, snap = snap(100), now = 101, budget = enough })).act)
			.toBe("forward")
		t.expect(Board.plan(ask({ all = false, snap = snap(100), now = 101, budget = tight })).act)
			.toBe("forward")
	end)

	it("another board never reads the best: its forwards and refreshes are never marked", function()
		t.expect(Board.plan(ask({ all = false, snap = snap(100), now = 101 })).best).toBe(false)
		t.expect(Board.plan(ask({ all = false, snap = nil })).best).toBe(false)
	end)

	it("an all-time refresh is marked unless the arcade still holds the player's best", function()
		t.expect(Board.plan(ask({ all = true, snap = nil, last = nil })).best).toBe(true)
		t.expect(Board.plan(ask({ all = true, snap = nil, last = 0, now = 5 })).best).toBe(false)
		t.expect(Board.plan(ask({ all = true, snap = snap(100), last = 115, now = 130 })).best).toBe(true)
	end)

	it("the held rows' status: wait before an answer, failed after a failed one, else ok", function()
		t.expect(Board.status(nil)).toBe("wait")
		t.expect(Board.status({ at = 5, failed = false, known = false, rows = {} })).toBe("wait")
		t.expect(Board.status({ at = 5, failed = true, known = true, rows = {} })).toBe("failed")
		t.expect(Board.status({ at = 5, failed = false, known = true, rows = {} })).toBe("ok")
	end)

	it("a player's held rank counts only when heard since the board's last refresh began", function()
		local s = snap(100)
		t.expect(Board.rankFor({ rank = 3, at = 100 }, s)).toBe(3)
		t.expect(Board.rankFor({ rank = 3, at = 120 }, s)).toBe(3)
		t.expect(Board.rankFor({ rank = 3, at = 99 }, s)).toBe(nil)
		t.expect(Board.rankFor(nil, s)).toBe(nil)
		t.expect(Board.rankFor({ rank = 3, at = 99 }, nil)).toBe(nil)
	end)

	it(
		"ten minutes of asks on all twelve boards every second stay inside the allowance and the budget",
		function()
			for _, players in { 1, 4, 30 } do
				local bucket: Board.Bucket = { tokens = 0, at = nil }
				local snaps: { [string]: Board.Snap } = {}
				local refreshes = 0
				local lastRefresh: { [string]: number } = {}
				local tooSoon = 0
				for now = 0, 599 do
					for _, title in { "pickman", "snake", "invaders", "asteroids" } do
						for _, id in Board.TABS do
							local key = `{title}|{id}`
							local s = snaps[key]
							local p = Board.plan(ask({
								snap = s,
								all = id == "all",
								last = now - 1,
								bucket = bucket,
								players = players,
								now = now,
							}))
							bucket = p.bucket
							if p.act == "refresh" then
								refreshes += 1
								if lastRefresh[key] ~= nil and now - lastRefresh[key] < Board.REFRESH then
									tooSoon += 1
								end
								lastRefresh[key] = now
								snaps[key] = { at = now, failed = false, known = true, rows = {} }
							end
						end
					end
				end
				-- each refresh is at most one sorted read: the allowance, and below 5 + 2 a player a minute
				t.expect(refreshes <= Board.BURST + Board.RATE * players * 10 + 1e-9).toBe(true)
				t.expect(refreshes <= (5 + 2 * players) * 10).toBe(true)
				t.expect(tooSoon).toBe(0)
				t.expect(refreshes > 0).toBe(true)
			end
		end
	)
end)
