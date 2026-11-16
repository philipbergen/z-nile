--!strict
-- f0206 AC2: the client's read of the server's answer (Board.parse). An answer is (title, board id, rows, rank,
-- status, best). It is read only for a title the client knows, a board id and a status of ok, failed or wait; rows that
-- make no sense are dropped and the rest sorted by rank and cut to ten; a row with junk revives reads as none; a rank
-- is kept only when it is a row's; the best is kept for the all-time board only, and a best that makes no sense is no
-- best. It never raises.
local Board = require("@logic/Board")
local t = require("@tests/lib/t")

local NAMES = { pickman = true, snake = true, invaders = true, asteroids = true }

local function good(rank: number, name: string): any
	return { rank = rank, name = name, score = 100 * (11 - rank), level = 2, revives = 1 }
end

return t.spec("f0206 parse", function(it)
	it("reads back an answer as the server sent it", function()
		local a = Board.parse(NAMES, "snake", "day", { good(1, "Ada"), good(2, "Bea") }, 2, "ok", nil)
		t.expect(a ~= nil).toBe(true)
		local got = a :: Board.Answer
		t.expect(got.name).toBe("snake")
		t.expect(got.id).toBe("day")
		t.expect(got.status).toBe("ok")
		t.expect(got.rank).toBe(2)
		t.expect(#got.rows).toBe(2)
		t.expect(got.rows[1].name).toBe("Ada")
		t.expect(got.rows[1].score).toBe(1000)
		t.expect(got.rows[1].level).toBe(2)
		t.expect(got.rows[1].revives).toBe(1)
		t.expect(got.best).toBe(nil)
	end)

	it("an all-time answer keeps the player's best; another board's best is dropped", function()
		local best = { score = 500, level = 3, revives = 2 }
		local all = Board.parse(NAMES, "pickman", "all", {}, nil, "ok", best) :: Board.Answer
		t.expect(all.best ~= nil).toBe(true)
		t.expect((all.best :: Board.Best).score).toBe(500)
		t.expect((all.best :: Board.Best).level).toBe(3)
		t.expect((all.best :: Board.Best).revives).toBe(2)
		local week = Board.parse(NAMES, "pickman", "week", {}, nil, "ok", best) :: Board.Answer
		t.expect(week.best).toBe(nil)
	end)

	it("a title it does not know, a board id that is none, or a status that is none: no answer", function()
		t.expect(Board.parse(NAMES, "lobby", "all", {}, nil, "ok", nil)).toBe(nil)
		t.expect(Board.parse(NAMES, 7, "all", {}, nil, "ok", nil)).toBe(nil)
		t.expect(Board.parse(NAMES, "pickman", "month", {}, nil, "ok", nil)).toBe(nil)
		t.expect(Board.parse(NAMES, "pickman", "all", {}, nil, "fine", nil)).toBe(nil)
		t.expect(Board.parse(NAMES, "pickman", "all", {}, nil, true, nil)).toBe(nil)
		t.expect(Board.parse(NAMES, "pickman", "all", {}, nil, nil, nil)).toBe(nil)
	end)

	it("each status reads as itself", function()
		for _, s in { "ok", "failed", "wait" } do
			t.expect((Board.parse(NAMES, "pickman", "all", {}, nil, s, nil) :: Board.Answer).status).toBe(s)
		end
	end)

	it("drops every row that makes no sense, and keeps the rest", function()
		local rows = {
			good(1, "Ada"),
			"row",
			{ rank = 0, name = "Zero", score = 1, level = 1, revives = 0 },
			{ rank = 11, name = "Eleven", score = 1, level = 1, revives = 0 },
			{ rank = 2.5, name = "Half", score = 1, level = 1, revives = 0 },
			{ rank = 3, name = 42, score = 1, level = 1, revives = 0 },
			{ rank = 4, name = "Neg", score = -1, level = 1, revives = 0 },
			{ rank = 5, name = "Flat", score = 1, level = 0, revives = 0 },
			{ rank = 6, name = "Inf", score = math.huge, level = 1, revives = 0 },
			{ rank = 7, name = "NaN", score = 0 / 0, level = 1, revives = 0 },
			{ rank = 8, name = "Text", score = "9", level = 1, revives = 0 },
			good(9, "Ivy"),
		}
		local a = Board.parse(NAMES, "pickman", "all", rows, nil, "ok", nil) :: Board.Answer
		local names = {}
		for _, r in a.rows do
			table.insert(names, r.name)
		end
		t.expect(table.concat(names, " ")).toBe("Ada Ivy")
	end)

	it("a row whose revives are junk reads as a row with none", function()
		for _, junk in { -1, 1.5, "2", true, 0 / 0, math.huge, {} } :: { any } do
			local r = { rank = 1, name = "Ada", score = 5, level = 1, revives = junk }
			local a = Board.parse(NAMES, "pickman", "all", { r }, nil, "ok", nil) :: Board.Answer
			t.expect(#a.rows).toBe(1)
			t.expect(a.rows[1].revives).toBe(0)
		end
		local a = Board.parse(
			NAMES,
			"pickman",
			"all",
			{ { rank = 1, name = "Ada", score = 5, level = 1 } },
			nil,
			"ok",
			nil
		)
		t.expect((a :: Board.Answer).rows[1].revives).toBe(0)
	end)

	it("sorts the rows by rank and keeps at most ten", function()
		local rows = {}
		for rank = 10, 1, -1 do
			table.insert(rows, good(rank, `P{rank}`))
		end
		table.insert(rows, good(3, "Again"))
		local a = Board.parse(NAMES, "pickman", "all", rows, nil, "ok", nil) :: Board.Answer
		t.expect(#a.rows).toBe(10)
		for i = 2, #a.rows do
			t.expect(a.rows[i - 1].rank <= a.rows[i].rank).toBe(true)
		end
		t.expect(a.rows[1].name).toBe("P1")
	end)

	it("keeps the rank only when it is a row's rank", function()
		local rows = { good(1, "Ada"), good(2, "Bea") }
		t.expect((Board.parse(NAMES, "pickman", "day", rows, 2, "ok", nil) :: Board.Answer).rank).toBe(2)
		for _, bad in { 3, 0, 1.5, "1", true } :: { any } do
			t.expect((Board.parse(NAMES, "pickman", "day", rows, bad, "ok", nil) :: Board.Answer).rank)
				.toBe(nil)
		end
	end)

	it("a best that makes no sense is no best; junk revives in a best read as none", function()
		for _, bad in
			{
				"best",
				{ score = -1, level = 1, revives = 0 },
				{ score = 5, level = 0, revives = 0 },
				{ score = 1.5, level = 1, revives = 0 },
				{ level = 1, revives = 0 },
			} :: { any }
		do
			t.expect((Board.parse(NAMES, "pickman", "all", {}, nil, "ok", bad) :: Board.Answer).best)
				.toBe(nil)
		end
		local a = Board.parse(NAMES, "pickman", "all", {}, nil, "ok", { score = 5, level = 1, revives = -3 })
		t.expect(((a :: Board.Answer).best :: Board.Best).revives).toBe(0)
	end)

	it("rows that are not a list read as no rows", function()
		for _, bad in { "rows", 5, true } :: { any } do
			local a = Board.parse(NAMES, "pickman", "all", bad, nil, "ok", nil) :: Board.Answer
			t.expect(#a.rows).toBe(0)
		end
	end)

	it("never raises, whatever it is sent", function()
		local junk: { any } =
			{ false, 1, -1, 0 / 0, "x", true, {}, { {} }, { rank = 1 }, setmetatable({}, {}) }
		for _, a in junk do
			for _, b in junk do
				local ok = pcall(function()
					Board.parse(NAMES, a, b, a, b, a, b)
					Board.parse(NAMES, "pickman", "all", a, b, "ok", a)
					Board.parse(NAMES, "pickman", "all", { a, b }, b, "failed", { score = a, level = b })
					Board.parse(NAMES)
				end)
				t.expect(ok).toBe(true)
			end
		end
	end)
end)
