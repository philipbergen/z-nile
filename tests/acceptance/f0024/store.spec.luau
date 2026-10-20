--!strict
-- f0024 AC4: the fake keeps one row per user per board, N is 10, and store names have no
-- environment prefix. Page reads unpack the ordered value field, and use at most two page sizes.
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
		t.expect((store.get(Hiscores.board("all", FRI), "7") :: any).name).toBe("Ada")
		t.expect((store.get(Hiscores.board("day", FRI), "7:2026-10-16") :: any).score).toBe(50)
		t.expect(store.get(Hiscores.board("day", FRI + 86400), "7:2026-10-17")).toBe(nil)
		t.expect((store.get(Hiscores.board("week", SUN), "7:2026-10-12") :: any).score).toBe(50)
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

	it(
		"the ordered page field is value, unpacked to the score, and a rejected page size is tried once at 50",
		function()
			t.expect(Hiscores.LEVEL_CAP).toBe(10000)
			t.expect(Hiscores.pack(50, 2)).toBe(500002)
			local raw: { any } = {}
			table.insert(raw, { key = "2", value = Hiscores.pack(10, 7) })
			table.insert(raw, { key = "5", score = 99 })
			table.insert(raw, { key = "3", value = Hiscores.pack(0, 1) })
			table.insert(raw, { key = "9", value = Hiscores.pack(7, 12000) })
			local mapped = Hiscores.scorePage(raw :: any)
			t.expect(#mapped).toBe(3)
			t.expect(mapped[1].key).toBe("2")
			t.expect(mapped[1].score).toBe(10)
			t.expect(mapped[2].key).toBe("3")
			t.expect(mapped[2].score).toBe(0)
			t.expect(mapped[3].key).toBe("9")
			t.expect(mapped[3].score).toBe(7)
			local capped = Hiscores.scorePage(raw :: any, 2)
			t.expect(#capped).toBe(2)
			t.expect(capped[2].key).toBe("3")
			t.expect(#Hiscores.scorePage(raw :: any, 10)).toBe(3)
			t.expect(Hiscores.pageAttempt(1)).toBe(10)
			t.expect(Hiscores.pageAttempt(2)).toBe(50)
			t.expect(Hiscores.pageAttempt(3)).toBe(nil)
		end
	)

	it("the fake's page is what scorePage makes of the packed values it holds", function()
		local store = Hiscores.fake()
		Hiscores.submit(store, attempt("7", 50, 2, "Ada"), FRI)
		Hiscores.submit(store, attempt("8", 50, 9, "Bea"), FRI)
		Hiscores.submit(store, attempt("9", 3, 1, "Cy"), FRI)
		local page = store.top(Hiscores.board("all", FRI), 10)
		t.expect(page).toEqual({
			Hiscores.scorePage({
				{ key = "8", value = Hiscores.pack(50, 9) },
				{ key = "7", value = Hiscores.pack(50, 2) },
				{ key = "9", value = Hiscores.pack(3, 1) },
			}),
		})
		local rows = Hiscores.top(store, "all", FRI)
		t.expect(rows[1].userId).toBe("8")
		t.expect(rows[1].score).toBe(50)
		t.expect(rows[1].level).toBe(9)
		t.expect(rows[3].score).toBe(3)
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
