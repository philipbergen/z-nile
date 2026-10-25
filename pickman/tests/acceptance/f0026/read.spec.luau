--!strict
-- f0026 AC3: the lobby asks for a board id, never a score. A fresh cache is shared. A stale cache
-- refetches, a failed fetch does not wipe the rows, and a failing board waits longer each time. Time is a parameter.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local FRI = 1792108800

local function sample(): { any }
	return { { rank = 1, name = "A", userId = "1", score = 10, level = 2 } }
end

return t.spec("f0026 board read", function(it)
	it("only all, day and week are board ids", function()
		t.expect(Hiscores.boardId("all")).toBe("all")
		t.expect(Hiscores.boardId("day")).toBe("day")
		t.expect(Hiscores.boardId("week")).toBe("week")
		t.expect(Hiscores.boardId("ALL")).toBe(nil)
		t.expect(Hiscores.boardId({ score = 99999 })).toBe(nil)
		t.expect(Hiscores.boardId(5000)).toBe(nil)
		t.expect(Hiscores.boardId(nil)).toBe(nil)
		t.expect(Hiscores.CACHE_TTL).toBe(15)
		t.expect(Hiscores.READ_GAP).toBe(1)
	end)

	it("the cache key is the period, so the day rolls and all-time does not", function()
		t.expect(Hiscores.cacheKey("all", FRI)).toBe("all")
		t.expect(Hiscores.cacheKey("all", FRI + 86400)).toBe("all")
		t.expect(Hiscores.cacheKey("day", FRI)).toBe("day:2026-10-16")
		t.expect(Hiscores.cacheKey("day", FRI + 86400)).toBe("day:2026-10-17")
		t.expect(Hiscores.cacheKey("week", FRI)).toBe("week:2026-10-12")
	end)

	it(
		"a fresh cache is returned, the boundary refetches, and a failed read waits before the next",
		function()
			local fetches = 0
			local result: { any }? = sample()
			local function fetch(): { any }?
				fetches += 1
				return result
			end
			local cache: any, rows: any, failure: any =
				Hiscores.lookup(nil, 0, Hiscores.CACHE_TTL, Hiscores.READ_GAP, false, fetch, nil)
			t.expect(fetches).toBe(1)
			t.expect(rows[1].score).toBe(10)
			t.expect(failure).toBe(nil)
			local same: any, rows2: any =
				Hiscores.lookup(cache, 14.9, Hiscores.CACHE_TTL, Hiscores.READ_GAP, false, fetch, nil)
			t.expect(fetches).toBe(1)
			t.expect(same).toBe(cache)
			t.expect(rows2[1].name).toBe("A")
			result = nil
			local kept: any, missing, failed: any =
				Hiscores.lookup(cache, 15, Hiscores.CACHE_TTL, Hiscores.READ_GAP, false, fetch, nil)
			t.expect(fetches).toBe(2)
			t.expect(missing).toBe(nil)
			t.expect(kept).toBe(cache)
			t.expect(failed.at).toBe(15)
			t.expect(failed.count).toBe(1)
			result = sample()
			local _, blocked, held =
				Hiscores.lookup(cache, 16, Hiscores.CACHE_TTL, Hiscores.READ_GAP, false, fetch, failed)
			t.expect(blocked).toBe(nil)
			t.expect(held).toBe(failed)
			t.expect(fetches).toBe(2)
			local fresh: any, freshRows: any, cleared =
				Hiscores.lookup(cache, 17, Hiscores.CACHE_TTL, Hiscores.READ_GAP, false, fetch, failed)
			t.expect(fetches).toBe(3)
			t.expect(fresh.at).toBe(17)
			t.expect(freshRows[1].score).toBe(10)
			t.expect(cleared).toBe(nil)
		end
	)

	it(
		"an empty board is cached, and a clock that is not a number or runs backwards does not fetch",
		function()
			local fetches = 0
			local function fetch(): { any }?
				fetches += 1
				return sample()
			end
			local cache: any, rows: any = Hiscores.lookup(
				nil,
				5,
				Hiscores.CACHE_TTL,
				Hiscores.READ_GAP,
				false,
				function(): { any }?
					fetches += 1
					return {}
				end,
				nil
			)
			t.expect(fetches).toBe(1)
			t.expect(rows).toEqual({})
			t.expect(cache.rows).toEqual({})
			local failure = { at = 10, count = 1 }
			local _, backwards, kept =
				Hiscores.lookup(nil, 4, Hiscores.CACHE_TTL, Hiscores.READ_GAP, false, fetch, failure)
			t.expect(backwards).toBe(nil)
			t.expect(kept).toBe(failure)
			t.expect(fetches).toBe(1)
			local same, nanRows =
				Hiscores.lookup(cache, 0 / 0, Hiscores.CACHE_TTL, Hiscores.READ_GAP, false, fetch, nil)
			t.expect(nanRows).toBe(nil)
			t.expect(same).toBe(cache)
			t.expect(fetches).toBe(1)
		end
	)

	it("an in-flight read does not fetch or move anything, and a cleared flag reads", function()
		local fetches = 0
		local function fetch(): { any }?
			fetches += 1
			return sample()
		end
		local stale: any = { at = 0, rows = sample() }
		local failure = { at = 0, count = 1 }
		local held: any, waiting, heldFailure =
			Hiscores.lookup(stale, 15, Hiscores.CACHE_TTL, Hiscores.READ_GAP, true, fetch, failure)
		t.expect(fetches).toBe(0)
		t.expect(waiting).toBe(nil)
		t.expect(held).toBe(stale)
		t.expect(held.at).toBe(0)
		t.expect(heldFailure).toBe(failure)
		local fresh: any, rows: any =
			Hiscores.lookup(stale, 15, Hiscores.CACHE_TTL, Hiscores.READ_GAP, false, fetch, failure)
		t.expect(fetches).toBe(1)
		t.expect(rows[1].score).toBe(10)
		t.expect(fresh.at).toBe(15)
		t.expect(stale.at).toBe(0)
	end)

	it(
		"a board whose read keeps failing is read again only after 2, 4, 8 and at most CACHE_TTL seconds",
		function()
			t.expect(Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 1)).toBe(2)
			t.expect(Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 2)).toBe(4)
			t.expect(Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 3)).toBe(8)
			t.expect(Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 4)).toBe(15)
			t.expect(Hiscores.failureWait(Hiscores.READ_GAP, Hiscores.CACHE_TTL, 9)).toBe(15)
			local fetches = 0
			local result: { any }? = nil
			local function fetch(): { any }?
				fetches += 1
				return result
			end
			local old: any = { at = -100, rows = sample() }
			local function at(now: number, failure: any): (any, any, any)
				return Hiscores.lookup(old, now, Hiscores.CACHE_TTL, Hiscores.READ_GAP, false, fetch, failure)
			end
			local cache, rows, failure = at(0, nil)
			t.expect(fetches).toBe(1)
			t.expect(cache).toBe(old)
			t.expect(rows).toBe(nil)
			t.expect(failure.at).toBe(0)
			t.expect(failure.count).toBe(1)
			local _, blockedRows, same = at(1, failure)
			t.expect(fetches).toBe(1)
			t.expect(blockedRows).toBe(nil)
			t.expect(same).toBe(failure)
			local _, _, second = at(2, failure)
			t.expect(fetches).toBe(2)
			t.expect(second.count).toBe(2)
			local _, _, still = at(5, second)
			t.expect(fetches).toBe(2)
			t.expect(still).toBe(second)
			result = sample()
			local healed, healedRows, cleared = at(6, second)
			t.expect(fetches).toBe(3)
			t.expect(healed.at).toBe(6)
			t.expect(healedRows[1].score).toBe(10)
			t.expect(cleared).toBe(nil)
		end
	)
end)
