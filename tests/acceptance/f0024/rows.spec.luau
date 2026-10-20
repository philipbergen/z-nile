--!strict
-- f0024 AC3: the board is the real top N. A short page stays short, a duplicate key keeps the first
-- score, a higher level wins a tie only inside the page, and a hard-coded list cannot pass.
local Hiscores = require("@logic/Hiscores")
local t = require("@tests/lib/t")

local FRI = 1792108800

local function attempt(userId: string, score: number, level: number): any
	return { userId = userId, score = score, level = level, name = "Ada" }
end

local function lookup(key: string): any
	if key == "8" then
		return nil
	elseif key == "9" then
		return { name = "High", userId = "9", level = 7, score = 10 }
	elseif key == "2" then
		return { name = "Low", userId = "2", level = 1, score = 1 }
	elseif key == "3" then
		return { name = "Mid", userId = "3", level = 2, score = 50 }
	elseif key == "4" then
		return { name = "Other", userId = "4", level = 2, score = 40 }
	end
	return nil
end

return t.spec("f0024 top N rows", function(it)
	it("eleven real scores keep the best ten, and the best is first", function()
		local store = Hiscores.fake()
		for i = 1, 11 do
			Hiscores.submit(store, attempt(tostring(100 + i), 1000 - i * 13, i), FRI)
		end
		local top = Hiscores.top(store, "all", FRI)
		t.expect(Hiscores.N).toBe(10)
		t.expect(#top).toBe(10)
		t.expect(top[1].userId).toBe("101")
		t.expect(top[1].rank).toBe(1)
		t.expect(top[1].score).toBe(987)
		local found = false
		for _, row in top do
			if row.userId == "111" then
				found = true
			end
		end
		t.expect(found).toBe(false)
	end)

	it("a short, unsorted page is not padded, and the page score wins", function()
		local pages = {
			{
				{ key = "2", score = 10 },
				{ key = "9", score = 10 },
				{ key = "3", score = 50 },
			},
			{
				{ key = "2", score = 999 },
				{ key = "4", score = 40 },
				{ key = "8", score = 5 },
			},
		}
		local rows: any = Hiscores.rows(pages, lookup, 10)
		t.expect(#rows).toBe(4)
		t.expect(rows[1].userId).toBe("3")
		t.expect(rows[1].rank).toBe(1)
		t.expect(rows[1].score).toBe(50)
		t.expect(rows[2].userId).toBe("4")
		t.expect(rows[2].score).toBe(40)
		t.expect(rows[3].userId).toBe("9")
		t.expect(rows[3].level).toBe(7)
		t.expect(rows[3].score).toBe(10)
		t.expect(rows[4].userId).toBe("2")
		t.expect(rows[4].level).toBe(1)
		t.expect(rows[4].rank).toBe(4)
		local short: any = Hiscores.rows({ { { key = "3", score = 50 } } }, lookup, 10)
		t.expect(#short).toBe(1)
		t.expect(short[1].rank).toBe(1)
		t.expect(#(Hiscores.rows(pages, lookup, 0) :: any)).toBe(0)
	end)

	it("an equal score keeps the higher level when the ordered page is one row", function()
		local store = Hiscores.fake()
		Hiscores.submit(store, attempt("1", 10, 1), FRI)
		Hiscores.submit(store, attempt("2", 10, 7), FRI)
		local page = store.top(Hiscores.board("all", FRI), 1)
		t.expect(#page).toBe(1)
		t.expect(#page[1]).toBe(1)
		t.expect(page[1][1].key).toBe("2")
		t.expect(page[1][1].score).toBe(10)
	end)

	it("an equal score and level orders the user id as a string, so 10 comes before 2", function()
		local tied: any = Hiscores.rows({
			{
				{ key = "10", score = 5 },
				{ key = "2", score = 5 },
			},
		}, function(key: string): any
			return { name = key, userId = key, level = 1, score = 5 }
		end, 10)
		t.expect(tied[1].userId).toBe("10")
		t.expect(tied[2].userId).toBe("2")
	end)

	it("a companion whose user id is not the key is skipped, and a period key still matches", function()
		local mismatch: any = Hiscores.rows({ { { key = "15", score = 80 } } }, function(_key: string): any
			return { name = "X", userId = "1", level = 1, score = 80 }
		end, 10)
		t.expect(#mismatch).toBe(0)
		local period: any = Hiscores.rows(
			{ { { key = "5:2026-10-16", score = 80 } } },
			function(_key: string): any
				return { name = "X", userId = "5", level = 1, score = 80 }
			end,
			10
		)
		t.expect(#period).toBe(1)
		t.expect(period[1].userId).toBe("5")
		t.expect(period[1].score).toBe(80)
	end)

	it("lobby rows drop the user id and keep rank, name, score and level", function()
		local rows: any = Hiscores.rows({ { { key = "3", score = 50 } } }, lookup, 10)
		local shown = Hiscores.lobbyRows(rows)
		t.expect(shown[1].rank).toBe(1)
		t.expect(shown[1].name).toBe("Mid")
		t.expect(shown[1].score).toBe(50)
		t.expect(shown[1].level).toBe(2)
		t.expect((shown[1] :: any).userId).toBe(nil)
	end)

	it(
		"a companion that cannot be read makes the whole board unknown, and an absent one is skipped",
		function()
			local page = { { { key = "2", score = 80 }, { key = "7", score = 50 } } }
			local unknown = Hiscores.rows(page, function(key: string): (any, string?)
				if key == "2" then
					return nil, "throttled"
				end
				return { name = "Ada", userId = "7", level = 2, score = 50 }, nil
			end, 10)
			t.expect(unknown).toBe(nil)
			local absent: any = Hiscores.rows(page, function(key: string): (any, string?)
				if key == "2" then
					return nil, nil
				end
				return { name = "Ada", userId = "7", level = 2, score = 50 }, nil
			end, 10)
			t.expect(#absent).toBe(1)
			t.expect(absent[1].userId).toBe("7")
			t.expect(absent[1].rank).toBe(1)
		end
	)
end)
