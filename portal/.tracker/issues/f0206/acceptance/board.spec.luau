--!strict
-- f0206 AC1: what a card's board shows (Logic/Board, pure). Three tabs, ALL-TIME, TODAY and THIS WEEK, stepped by W,
-- Up and the left trigger back and S, Down and the right trigger forward, wrapping; a header naming the title's
-- progress figure; one line per row: rank, name, score, the figure and the revives used ("—" for none); a note for a
-- board not answered yet, empty or unreadable; the "your best" line on the all-time tab; a layout that keeps every
-- line readable in the card's Boards slot on every screen the carousel fits, scrolling the rows where they do not fit;
-- and when the client asks again.
local Board = require("@logic/Board")
local Card = require("@logic/Card")
local Carousel = require("@logic/Carousel")
local t = require("@tests/lib/t")

-- the carousel's screen shapes (f0205's carousel spec): safe-area pixels
local SCREENS =
	{ { 1920, 1080 }, { 1280, 720 }, { 1024, 768 }, { 844, 390 }, { 390, 844 }, { 320, 480 }, { 2560, 1080 } }

-- the Boards slot's height on the front card of a screen: the card's box, times the Boards region (f0205)
local function slotHeight(width: number, height: number): number
	return Carousel.box(0, width, height).height * Card.REGIONS.Boards.height
end

local function row(rank: number, name: string, score: number, level: number, revives: number): Board.Row
	return { rank = rank, name = name, score = score, level = level, revives = revives }
end

local function answer(
	status: Board.Status,
	rows: { Board.Row },
	rank: number?,
	best: Board.Best?
): Board.Answer
	return { name = "pickman", id = "all", rows = rows, rank = rank, status = status, best = best }
end

return t.spec("f0206 board", function(it)
	it("three tabs, ALL-TIME, TODAY and THIS WEEK, left to right, and no other board id", function()
		t.expect(table.concat(Board.TABS, " ")).toBe("all day week")
		t.expect(Board.TAB_TEXT.all).toBe("ALL-TIME")
		t.expect(Board.TAB_TEXT.day).toBe("TODAY")
		t.expect(Board.TAB_TEXT.week).toBe("THIS WEEK")
		for _, id in Board.TABS do
			t.expect(Board.id(id)).toBe(id)
		end
		for _, bad in { "ALL", "month", "", 1, true, {} } :: { any } do
			t.expect(Board.id(bad)).toBe(nil)
		end
		t.expect(Board.id(nil)).toBe(nil)
	end)

	it("a tab step moves one tab and wraps both ways; a step that is not whole stays", function()
		t.expect(Board.tab("all", 1)).toBe("day")
		t.expect(Board.tab("day", 1)).toBe("week")
		t.expect(Board.tab("week", 1)).toBe("all")
		t.expect(Board.tab("all", -1)).toBe("week")
		t.expect(Board.tab("week", -1)).toBe("day")
		t.expect(Board.tab("day", 0.5)).toBe("day")
		t.expect(Board.tab("day", 0 / 0)).toBe("day")
	end)

	it("W, Up and the left trigger step back; S, Down and the right trigger forward; nothing else", function()
		for _, key in { "W", "Up", "ButtonL2" } do
			t.expect(Board.step(key)).toBe(-1)
		end
		for _, key in { "S", "Down", "ButtonR2" } do
			t.expect(Board.step(key)).toBe(1)
		end
		for _, key in
			{ "A", "D", "Left", "Right", "Return", "ButtonA", "ButtonL1", "ButtonR1", "Tab", "Space" }
		do
			t.expect(Board.step(key)).toBe(nil)
		end
		local keys = {}
		for k in Board.KEYS do
			table.insert(keys, k)
		end
		table.sort(keys)
		t.expect(table.concat(keys, " ")).toBe("ButtonL2 ButtonR2 Down S Up W")
	end)

	it(
		"the tab keys sit under one action of their own, above the default controls, below the test purchase screen",
		function()
			t.expect(type(Board.ACTION)).toBe("string")
			t.expect(Board.ACTION ~= Carousel.ACTION).toBe(true)
			-- above the default controls (Enum.ContextActionPriority.Default, 2000), below the test purchase screen (3000)
			t.expect(Board.PRIORITY > 2000 and Board.PRIORITY < 3000).toBe(true)
			t.expect(table.isfrozen(Board.KEYS)).toBe(true)
		end
	)

	it("revives show their count, and none shows a dash: 0, or a count that is not whole", function()
		t.expect(Board.NONE).toBe("—")
		t.expect(Board.revives(1)).toBe("1")
		t.expect(Board.revives(12)).toBe("12")
		for _, none in { 0, -1, 1.5, 0 / 0, math.huge, "3", true, {} } :: { any } do
			t.expect(Board.revives(none)).toBe("—")
		end
		t.expect(Board.revives(nil)).toBe("—")
	end)

	it("the header names the title's progress figure between score and revives", function()
		t.expect(table.concat(Board.header("Level"), "|")).toBe("#|NAME|SCORE|LEVEL|REVIVES")
		t.expect(table.concat(Board.header("Map"), "|")).toBe("#|NAME|SCORE|MAP|REVIVES")
		t.expect(table.concat(Board.header("Wave"), "|")).toBe("#|NAME|SCORE|WAVE|REVIVES")
	end)

	it("a row shows rank, name, score, the figure and the revives used, in the columns' order", function()
		t.expect(table.concat(Board.cells(row(1, "Ada", 12340, 7, 2)), "|")).toBe("1|Ada|12340|7|2")
		t.expect(table.concat(Board.cells(row(10, "Bea", 0, 1, 0)), "|")).toBe("10|Bea|0|1|—")
		local names = {}
		local sum = 0
		for _, c in Board.COLUMNS do
			table.insert(names, c.name)
			sum += c.width
		end
		t.expect(table.concat(names, " ")).toBe("Rank Name Score Progress Revives")
		t.expect(sum).toBeNear(1, 1e-9)
	end)

	it("the your-best line: score, the figure and revives, or a dash for a player with no best", function()
		t.expect(Board.bestLine({ score = 1200, level = 3, revives = 2 }, "Level"))
			.toBe("YOUR BEST 1200 · LEVEL 3 · REVIVES 2")
		t.expect(Board.bestLine({ score = 80, level = 1, revives = 0 }, "Map"))
			.toBe("YOUR BEST 80 · MAP 1 · REVIVES —")
		t.expect(Board.bestLine(nil, "Wave")).toBe("YOUR BEST —")
	end)

	it("before an answer, and on a wait, the board says LOADING and shows no rows and no best", function()
		for _, a in { nil :: Board.Answer?, answer("wait", { row(1, "Ada", 5, 1, 0) }, 1, nil) } do
			local v = Board.view(a, "all", "Level")
			t.expect(v.note).toBe("LOADING")
			t.expect(#v.lines).toBe(0)
			t.expect(v.best).toBe("")
			t.expect(table.concat(v.header, "|")).toBe("#|NAME|SCORE|LEVEL|REVIVES")
		end
	end)

	it("an answer's rows show in order, the player's own row marked, and the best line below", function()
		local v = Board.view(
			answer(
				"ok",
				{ row(1, "Ada", 900, 4, 1), row(2, "Bea", 600, 2, 0) },
				2,
				{ score = 600, level = 2, revives = 0 }
			),
			"all",
			"Level"
		)
		t.expect(v.note).toBe("")
		t.expect(#v.lines).toBe(2)
		t.expect(table.concat(v.lines[1].cells, "|")).toBe("1|Ada|900|4|1")
		t.expect(table.concat(v.lines[2].cells, "|")).toBe("2|Bea|600|2|—")
		t.expect(v.lines[1].mine).toBe(false)
		t.expect(v.lines[2].mine).toBe(true)
		t.expect(v.best).toBe("YOUR BEST 600 · LEVEL 2 · REVIVES —")
	end)

	it("with no rank no row is marked; an all-time answer with no best says YOUR BEST —", function()
		local v = Board.view(answer("ok", { row(1, "Ada", 900, 4, 1) }, nil, nil), "all", "Wave")
		t.expect(v.lines[1].mine).toBe(false)
		t.expect(v.best).toBe("YOUR BEST —")
	end)

	it("an empty board says NO SCORES YET; a failed read with no rows says SCORES UNAVAILABLE", function()
		t.expect(Board.view(answer("ok", {}, nil, nil), "all", "Level").note).toBe("NO SCORES YET")
		t.expect(Board.view(answer("failed", {}, nil, nil), "all", "Level").note).toBe("SCORES UNAVAILABLE")
		local held = Board.view(answer("failed", { row(1, "Ada", 900, 4, 0) }, nil, nil), "all", "Level")
		t.expect(held.note).toBe("")
		t.expect(#held.lines).toBe(1)
	end)

	it("the best line shows on the all-time tab only", function()
		local a = answer("ok", { row(1, "Ada", 900, 4, 0) }, 1, { score = 900, level = 4, revives = 0 })
		t.expect(Board.view(a, "day", "Level").best).toBe("")
		t.expect(Board.view(a, "week", "Level").best).toBe("")
		t.expect(Board.view(a, "all", "Level").best ~= "").toBe(true)
	end)

	it(
		"the layout: a touch-sized tab bar, then the header, the rows' view and the best line, filling the slot",
		function()
			t.expect(Board.TAB_PX).toBe(44)
			local l = Board.layout(311)
			t.expect(l.tabs).toBe(44)
			t.expect(l.line).toBeNear((311 - 44) / 12, 1e-9)
			t.expect(l.tabs + l.line + l.view + l.line).toBeNear(311, 1e-9)
			t.expect(l.canvas).toBeNear(10 * l.line, 1e-9)
		end
	)

	it(
		"every line is readable on every screen the carousel fits; the rows scroll only where they do not fit",
		function()
			for _, s in SCREENS do
				local h = slotHeight(s[1], s[2])
				local l = Board.layout(h)
				t.expect(l.line >= Board.MIN_LINE_PX).toBe(true)
				t.expect(l.line <= Board.MAX_LINE_PX).toBe(true)
				t.expect(l.view >= 0).toBe(true)
				t.expect(l.canvas).toBeNear(Board.N * l.line, 1e-9)
			end
			-- a slot of 12 lines at the smallest readable line and up (a 720 px screen's front card: 0.9 x 720 x 0.32 is
			-- 207 px) shows all ten rows without scrolling
			for _, h in { Board.TAB_PX + 12 * Board.MIN_LINE_PX, 207, 221, 311, 400 } do
				local l = Board.layout(h)
				t.expect(l.canvas <= l.view + 1e-9).toBe(true)
			end
			-- a smaller slot (a phone held sideways: 0.9 x 390 x 0.32 is 112 px) scrolls them at the smallest line
			local phone = Board.layout(112)
			t.expect(phone.line).toBe(Board.MIN_LINE_PX)
			t.expect(phone.canvas > phone.view).toBe(true)
			t.expect(phone.view).toBeNear(112 - Board.TAB_PX - 2 * Board.MIN_LINE_PX, 1e-9)
			t.expect(Board.MIN_LINE_PX).toBe(13)
			t.expect(Board.MAX_LINE_PX).toBe(28)
		end
	)

	it("a slot of no size, or a size that is not finite, lays out at the smallest line", function()
		for _, h in { 0, -5, 0 / 0, math.huge } do
			local l = Board.layout(h)
			t.expect(l.line).toBe(Board.MIN_LINE_PX)
			t.expect(l.view).toBe(0)
		end
	end)

	it(
		"the client asks for a new title or tab at once, then again after REASK, or WAIT_RETRY after a wait",
		function()
			t.expect(Board.REASK).toBe(30)
			t.expect(Board.WAIT_RETRY).toBe(2)
			t.expect(Board.askDue(nil, "pickman", "all", 5)).toBe(true)
			local last: Board.Asked = { name = "pickman", id = "all", at = 100, wait = false }
			t.expect(Board.askDue(last, "pickman", "all", 100)).toBe(false)
			t.expect(Board.askDue(last, "pickman", "all", 129.9)).toBe(false)
			t.expect(Board.askDue(last, "pickman", "all", 130)).toBe(true)
			t.expect(Board.askDue(last, "snake", "all", 100.1)).toBe(true)
			t.expect(Board.askDue(last, "pickman", "day", 100.1)).toBe(true)
			local waited: Board.Asked = { name = "pickman", id = "all", at = 100, wait = true }
			t.expect(Board.askDue(waited, "pickman", "all", 101.9)).toBe(false)
			t.expect(Board.askDue(waited, "pickman", "all", 102)).toBe(true)
		end
	)

	it("a clock that went back asks again; a time that is not finite asks nothing", function()
		local last: Board.Asked = { name = "pickman", id = "all", at = 100, wait = false }
		t.expect(Board.askDue(last, "pickman", "all", 99)).toBe(true)
		t.expect(Board.askDue(last, "pickman", "all", 0 / 0)).toBe(false)
		t.expect(Board.askDue(nil, "pickman", "all", math.huge)).toBe(false)
	end)

	it("its tables are frozen", function()
		for _, v in
			{ Board, Board.TABS, Board.TAB_TEXT, Board.COLUMNS, Board.KEYS, Board.COST, Board.RESERVE } :: { any }
		do
			t.expect(table.isfrozen(v)).toBe(true)
		end
		for _, c in Board.COLUMNS do
			t.expect(table.isfrozen(c)).toBe(true)
		end
	end)
end)
