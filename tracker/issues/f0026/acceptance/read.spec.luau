--!strict
-- f0026 AC3: the lobby asks for a board id, never a score. A fresh cache is shared. A stale cache
-- refetches only after the gap, and a failed fetch does not wipe the rows. Time is a parameter.
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

	it("a fresh cache is returned, the boundary refetches, and the gap blocks a stampede", function()
		local fetches = 0
		local function fetch(): { any }?
			fetches += 1
			return sample()
		end
		local cache: any, last, rows: any =
			Hiscores.lookup(nil, 0, Hiscores.CACHE_TTL, nil, Hiscores.READ_GAP, false, fetch)
		t.expect(fetches).toBe(1)
		t.expect(rows[1].score).toBe(10)
		local _, last2, rows2: any =
			Hiscores.lookup(cache, 1, Hiscores.CACHE_TTL, last, Hiscores.READ_GAP, false, fetch)
		t.expect(fetches).toBe(1)
		t.expect(rows2[1].name).toBe("A")
		t.expect(last2).toBe(0)
		local kept: any, failedAt, missing = Hiscores.lookup(
			cache,
			15,
			Hiscores.CACHE_TTL,
			last,
			Hiscores.READ_GAP,
			false,
			function(): { any }?
				return nil
			end
		)
		t.expect(fetches).toBe(1)
		t.expect(missing).toBe(nil)
		t.expect(kept).toBe(cache)
		t.expect(failedAt).toBe(15)
		local _, _, blocked =
			Hiscores.lookup(cache, 15.5, Hiscores.CACHE_TTL, failedAt, Hiscores.READ_GAP, false, fetch)
		t.expect(blocked).toBe(nil)
		t.expect(fetches).toBe(1)
		local _, _, fresh: any =
			Hiscores.lookup(cache, 16, Hiscores.CACHE_TTL, failedAt, Hiscores.READ_GAP, false, fetch)
		t.expect(fetches).toBe(2)
		t.expect(fresh[1].score).toBe(10)
	end)

	it("an empty board is cached, and a clock that is not a number does not fetch", function()
		local fetches = 0
		local cache: any, last, rows: any = Hiscores.lookup(
			nil,
			5,
			Hiscores.CACHE_TTL,
			nil,
			Hiscores.READ_GAP,
			false,
			function(): { any }?
				fetches += 1
				return {}
			end
		)
		t.expect(fetches).toBe(1)
		t.expect(rows).toEqual({})
		t.expect(cache.rows).toEqual({})
		t.expect(last).toBe(5)
		local _, _, backwards = Hiscores.lookup(
			nil,
			4,
			Hiscores.CACHE_TTL,
			10,
			Hiscores.READ_GAP,
			false,
			function(): { any }?
				fetches += 1
				return sample()
			end
		)
		t.expect(backwards).toBe(nil)
		t.expect(fetches).toBe(1)
		local same, sameLast, nanRows = Hiscores.lookup(
			cache,
			0 / 0,
			Hiscores.CACHE_TTL,
			last,
			Hiscores.READ_GAP,
			false,
			function(): { any }?
				fetches += 1
				return sample()
			end
		)
		t.expect(nanRows).toBe(nil)
		t.expect(same).toBe(cache)
		t.expect(sameLast).toBe(last)
		t.expect(fetches).toBe(1)
	end)

	it("an in-flight read does not fetch, and a cleared flag retries after the gap", function()
		local fetches = 0
		local function fetch(): { any }?
			fetches += 1
			return sample()
		end
		local stale: any = { at = 0, rows = sample() }
		local _, _, rows: any =
			Hiscores.lookup(stale, 15, Hiscores.CACHE_TTL, 0, Hiscores.READ_GAP, false, fetch)
		local held: any, heldLast, waiting =
			Hiscores.lookup(stale, 15, Hiscores.CACHE_TTL, 0, Hiscores.READ_GAP, true, fetch)
		t.expect(fetches).toBe(1)
		t.expect(rows[1].score).toBe(10)
		t.expect(waiting).toBe(nil)
		t.expect(held).toBe(stale)
		t.expect(held.at).toBe(0)
		t.expect(heldLast).toBe(0)
		local kept: any, failedAt, missing = Hiscores.lookup(
			stale,
			15,
			Hiscores.CACHE_TTL,
			0,
			Hiscores.READ_GAP,
			false,
			function(): { any }?
				return nil
			end
		)
		t.expect(missing).toBe(nil)
		t.expect(kept).toBe(stale)
		t.expect(kept.at).toBe(0)
		t.expect(failedAt).toBe(15)
		local blocked, blockedLast, blockedRows = Hiscores.lookup(
			stale,
			(failedAt :: number) + Hiscores.READ_GAP,
			Hiscores.CACHE_TTL,
			failedAt,
			Hiscores.READ_GAP,
			true,
			fetch
		)
		t.expect(fetches).toBe(1)
		t.expect(blockedRows).toBe(nil)
		t.expect(blocked).toBe(stale)
		t.expect(blockedLast).toBe(failedAt)
		local _, _, retried: any = Hiscores.lookup(
			stale,
			(failedAt :: number) + Hiscores.READ_GAP,
			Hiscores.CACHE_TTL,
			failedAt,
			Hiscores.READ_GAP,
			false,
			fetch
		)
		t.expect(fetches).toBe(2)
		t.expect(retried[1].score).toBe(10)
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
				local cache, _, rows, nextFailure = Hiscores.lookup(
					old,
					now,
					Hiscores.CACHE_TTL,
					nil,
					Hiscores.READ_GAP,
					false,
					fetch,
					failure
				)
				return cache, rows, nextFailure
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
