--!strict
-- f0024 AC4: the fake keeps one row per user per board, N is 10, and store names have no
-- environment prefix. Page reads use the ordered value field and at most two page sizes.
local Hiscores = require("@logic/Hiscores")
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local FRI = 1792108800
local SUN = 1792281600

local function attempt(userId: string, score: number, level: number, name: string?): any
	return { userId = userId, score = score, level = level, name = if name == nil then "Ada" else name }
end

return t.spec("f0024 in-memory store", function(it)
	it("N matches the lobby panel and is not raised", function()
		t.expect(Lobby.MAX_ROWS).toBe(10)
		t.expect(Hiscores.N).toBe(10)
		t.expect(Hiscores.N).toBe(Lobby.MAX_ROWS)
		t.expect(Hiscores.ORDERED_STORE).toBe("Hiscores")
		t.expect(Hiscores.COMPANION_STORE).toBe("HiscoreEntries")
	end)

	it("scopes do not share a row, and one user is one row", function()
		local store = Hiscores.fake()
		Hiscores.submit(store, attempt("7", 50, 2, "Ada"), FRI)
		t.expect(store.get(Hiscores.board("all", FRI), "7").name).toBe("Ada")
		t.expect(store.get(Hiscores.board("day", FRI), "7:2026-10-16").score).toBe(50)
		t.expect(store.get(Hiscores.board("day", FRI + 86400), "7:2026-10-17")).toBe(nil)
		t.expect(store.get(Hiscores.board("week", SUN), "7:2026-10-12").score).toBe(50)
		Hiscores.submit(store, attempt("8", 40, 1, "Bea"), FRI)
		local top = store.top(Hiscores.board("all", FRI), 10)
		t.expect(#top).toBe(1)
		t.expect(#top[1]).toBe(2)
		t.expect(top[1][1].key).toBe("7")
		t.expect(top[1][1].score).toBe(50)
		t.expect(top[1][2].key).toBe("8")
		local day = Hiscores.top(store, "day", FRI)
		t.expect(#day).toBe(2)
		t.expect(day[1].userId).toBe("7")
		t.expect(day[2].userId).toBe("8")
	end)

	it("the ordered page field is value, and a rejected page size is tried once at 50", function()
		local raw: { any } = {}
		table.insert(raw, { key = "4", value = 12 })
		table.insert(raw, { key = "5", score = 99 })
		local mapped = Hiscores.scorePage(raw :: any)
		t.expect(#mapped).toBe(1)
		t.expect(mapped[1].key).toBe("4")
		t.expect(mapped[1].score).toBe(12)
		t.expect(Hiscores.pageAttempt(1)).toBe(10)
		t.expect(Hiscores.pageAttempt(2)).toBe(50)
		t.expect(Hiscores.pageAttempt(3)).toBe(nil)
	end)

	it("a rejected scope falls back to a global name with no beta or prod prefix", function()
		t.expect(Hiscores.globalName("Hiscores", "day:2026-10-16")).toBe("Hiscores_day_2026_10_16")
		local ordered, scope = Hiscores.storeTarget("ordered", Hiscores.board("day", FRI), true)
		t.expect(ordered).toBe("Hiscores")
		t.expect(scope).toBe("day:2026-10-16")
		local companion, globalScope = Hiscores.storeTarget("companion", Hiscores.board("week", SUN), false)
		t.expect(companion).toBe("HiscoreEntries_week_2026_10_12")
		t.expect(globalScope).toBe("global")
	end)
end)
