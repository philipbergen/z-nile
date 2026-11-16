--!strict
-- f0206 AC1: what a card's board shows and which boards the client asks for (Logic/Board, pure). Three tabs, ALL-TIME,
-- TODAY and THIS WEEK, stepped by W, Up and the left trigger back and S, Down and the right trigger forward, wrapping; a
-- header naming the title's progress figure; one line per row: rank, name, score, the figure and the revives used ("—"
-- for none); a note for a board not answered yet, empty or unreadable; the "your best" line under every tab, the best
-- not heard yet shown pending and never as "no best"; columns that keep every text whole with a gap between them, and
-- every text at least Card.MIN_TEXT pixels in the card's Boards slot on every screen the carousel fits, the rows
-- scrolling where they do not fit; every card's board asked for, each again after REASK, or WAIT_RETRY after a wait or
-- while the best is pending.
local Board = require("@logic/Board")
local Card = require("@logic/Card")
local Carousel = require("@logic/Carousel")
local t = require("@tests/lib/t")

-- the carousel's screen shapes (f0205's carousel spec): safe-area pixels
local SCREENS =
	{ { 1920, 1080 }, { 1280, 720 }, { 1024, 768 }, { 844, 390 }, { 390, 844 }, { 320, 480 }, { 2560, 1080 } }

-- the Boards slot on the front card of a screen: the card's box, inset either side by Card.INSET, and the Boards
-- region of its height (f0205)
local function slot(width: number, height: number): (number, number)
	local box = Carousel.box(0, width, height)
	return box.width * (1 - 2 * Card.INSET), box.height * Card.REGIONS.Boards.height
end

-- the widest text each column must show whole at the board's text size: headers, the largest values, a name's
-- first seven characters, the dash and the pending mark
local WIDEST: { [string]: { string } } = {
	Rank = { "#", "10" },
	Name = { "NAME", "ABCDEFG" },
	Score = { "SCORE", "123456", Board.NONE, Board.PENDING },
	Progress = { "LEVEL", "WAVE", "MAP", "999", Board.NONE, Board.PENDING },
	Revives = { "REVIVES", "99", Board.NONE, Board.PENDING },
}

local function row(rank: number, name: string, score: number, level: number, revives: number): Board.Row
	return { rank = rank, name = name, score = score, level = level, revives = revives }
end

local function answer(status: Board.Status, rows: { Board.Row }, rank: number?): Board.Answer
	return {
		name = "pickman",
		id = "all",
		rows = rows,
		rank = rank,
		status = status,
		best = nil,
		pending = false,
	}
end

local KNOWN: Board.Mine = { known = true, best = { score = 600, level = 2, revives = 0 } }
local NONE: Board.Mine = { known = true, best = nil }

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
		-- the carousel's keys (f0205) and the play buttons' (f0208: 2, keypad 2, X, Backspace, B, I, Y) are not tab keys
		local others =
			{ "Tab", "Space", "Two", "KeypadTwo", "ButtonX", "Backspace", "ButtonB", "I", "ButtonY" }
		for key in Carousel.KEYS do
			table.insert(others, key)
		end
		for _, key in others do
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
		local names, aligns = {}, {}
		for _, c in Board.COLUMNS do
			table.insert(names, c.name)
			table.insert(aligns, c.align)
		end
		t.expect(table.concat(names, " ")).toBe("Rank Name Score Progress Revives")
		-- the name reads from the left, every number and the figures from the right
		t.expect(table.concat(aligns, " ")).toBe("Right Left Right Right Right")
	end)

	it(
		"the columns: each label its characters wide, a GUTTER between neighbours, the line CHARS wide",
		function()
			t.expect(Board.GUTTER > 0).toBe(true)
			local chars = 0
			for i, c in Board.COLUMNS do
				t.expect(c.width).toBeNear(c.chars / Board.CHARS, 1e-9)
				chars += c.chars + Board.GUTTER
				if i > 1 then
					local before = Board.COLUMNS[i - 1]
					-- the gap from one label's right edge to the next one's left edge
					t.expect(c.x - (before.x + before.width)).toBeNear(Board.GUTTER / Board.CHARS, 1e-9)
				end
			end
			t.expect(chars).toBeNear(Board.CHARS, 1e-9)
			local first, last = Board.COLUMNS[1], Board.COLUMNS[#Board.COLUMNS]
			t.expect(first.x >= 0).toBe(true)
			t.expect(last.x + last.width <= 1 + 1e-9).toBe(true)
		end
	)

	it(
		"the your-best line, in the columns: YOUR BEST, then score, figure and revives, or dashes for no best",
		function()
			t.expect(Board.BEST).toBe("YOUR BEST")
			t.expect(table.concat(Board.bestCells({ score = 1200, level = 3, revives = 2 }), "|"))
				.toBe("|YOUR BEST|1200|3|2")
			t.expect(table.concat(Board.bestCells({ score = 80, level = 1, revives = 0 }), "|"))
				.toBe("|YOUR BEST|80|1|—")
			t.expect(table.concat(Board.bestCells(nil), "|")).toBe("|YOUR BEST|—|—|—")
		end
	)

	it(
		"a best not heard yet is pending, drawn with its own mark and never as the dashes of no best",
		function()
			t.expect(Board.PENDING ~= Board.NONE).toBe(true)
			t.expect(table.concat(Board.pendingCells(), "|"))
				.toBe(`|YOUR BEST|{Board.PENDING}|{Board.PENDING}|{Board.PENDING}`)
			local a = answer("ok", { row(1, "Ada", 900, 4, 1) }, nil)
			t.expect(table.concat(Board.view(a, "Level", nil).best or {}, "|"))
				.toBe(table.concat(Board.pendingCells(), "|"))
			local unknown: Board.Mine = { known = false, best = nil }
			t.expect(table.concat(Board.view(a, "Level", unknown).best or {}, "|"))
				.toBe(table.concat(Board.pendingCells(), "|"))
			t.expect(table.concat(Board.view(a, "Level", NONE).best or {}, "|"))
				.toBe("|YOUR BEST|—|—|—")
		end
	)

	it(
		"the player's own best is learnt from any answer that is not pending, and a pending one leaves it",
		function()
			local a = answer("ok", {}, nil)
			local learnt = Board.learn(nil, {
				name = a.name,
				id = "day",
				rows = {},
				rank = nil,
				status = "ok",
				best = { score = 9, level = 1, revives = 0 },
				pending = false,
			})
			t.expect(learnt.known).toBe(true)
			t.expect(learnt.best ~= nil).toBe(true)
			t.expect((learnt.best :: Board.Best).score).toBe(9)
			local kept = Board.learn(learnt, {
				name = a.name,
				id = "all",
				rows = {},
				rank = nil,
				status = "ok",
				best = nil,
				pending = true,
			})
			t.expect(kept.known).toBe(true)
			t.expect(kept.best ~= nil).toBe(true)
			t.expect((kept.best :: Board.Best).score).toBe(9)
			local none = Board.learn(learnt, a)
			t.expect(none.known).toBe(true)
			t.expect(none.best).toBe(nil)
			local still = Board.learn(nil, {
				name = a.name,
				id = "all",
				rows = {},
				rank = nil,
				status = "ok",
				best = nil,
				pending = true,
			})
			t.expect(still.known).toBe(false)
		end
	)

	it("before an answer, and on a wait, the board says LOADING and shows no rows and no best", function()
		for _, a in { nil :: Board.Answer?, answer("wait", { row(1, "Ada", 5, 1, 0) }, 1) } do
			local v = Board.view(a, "Level", KNOWN)
			t.expect(v.note).toBe("LOADING")
			t.expect(#v.lines).toBe(0)
			t.expect(v.best).toBe(nil)
			t.expect(table.concat(v.header, "|")).toBe("#|NAME|SCORE|LEVEL|REVIVES")
		end
	end)

	it("an answer's rows show in order, the player's own row marked, and the best line below", function()
		local v = Board.view(
			answer("ok", { row(1, "Ada", 900, 4, 1), row(2, "Bea", 600, 2, 0) }, 2),
			"Level",
			KNOWN
		)
		t.expect(v.note).toBe("")
		t.expect(#v.lines).toBe(2)
		t.expect(table.concat(v.lines[1].cells, "|")).toBe("1|Ada|900|4|1")
		t.expect(table.concat(v.lines[2].cells, "|")).toBe("2|Bea|600|2|—")
		t.expect(v.lines[1].mine).toBe(false)
		t.expect(v.lines[2].mine).toBe(true)
		t.expect(table.concat(v.best or {}, "|")).toBe("|YOUR BEST|600|2|—")
	end)

	it("with no rank no row is marked; a player with no run has dashes in the best line", function()
		local v = Board.view(answer("ok", { row(1, "Ada", 900, 4, 1) }, nil), "Wave", NONE)
		t.expect(v.lines[1].mine).toBe(false)
		t.expect(table.concat(v.best or {}, "|")).toBe("|YOUR BEST|—|—|—")
	end)

	it("an empty board says NO SCORES YET; a failed read with no rows says SCORES UNAVAILABLE", function()
		t.expect(Board.view(answer("ok", {}, nil), "Level", KNOWN).note).toBe("NO SCORES YET")
		t.expect(Board.view(answer("failed", {}, nil), "Level", KNOWN).note).toBe("SCORES UNAVAILABLE")
		local held = Board.view(answer("failed", { row(1, "Ada", 900, 4, 0) }, nil), "Level", KNOWN)
		t.expect(held.note).toBe("")
		t.expect(#held.lines).toBe(1)
	end)

	it(
		"the best line shows under every board an answer was heard for: TODAY's and THIS WEEK's too",
		function()
			for _, id in Board.TABS do
				local a = answer("ok", { row(1, "Ada", 900, 4, 0) }, 1)
				a.id = id
				t.expect(table.concat(Board.view(a, "Level", KNOWN).best or {}, "|"))
					.toBe("|YOUR BEST|600|2|—")
			end
		end
	)

	it(
		"the layout: a touch-sized tab bar, then the header, the rows' view and the best line, filling the slot",
		function()
			t.expect(Board.TAB_PX).toBe(44)
			local l = Board.layout(600, 311, Card.GLYPH)
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
				local w, h = slot(s[1], s[2])
				local l = Board.layout(w, h, Card.GLYPH)
				t.expect(l.line >= Board.MIN_LINE_PX).toBe(true)
				t.expect(l.line <= Board.MAX_LINE_PX).toBe(true)
				t.expect(l.view >= 0).toBe(true)
				t.expect(l.canvas).toBeNear(Board.N * l.line, 1e-9)
			end
			-- a slot of 12 lines at the smallest readable line and up (a 720 px screen's front card: 0.9 x 720 x 0.32 is
			-- 207 px) shows all ten rows without scrolling
			for _, h in { Board.TAB_PX + 12 * Board.MIN_LINE_PX, 207, 221, 311, 400 } do
				local l = Board.layout(300, h, Card.GLYPH)
				t.expect(l.canvas <= l.view + 1e-9).toBe(true)
			end
			-- a smaller slot (a phone held sideways: 0.9 x 390 x 0.32 is 112 px) scrolls them at the smallest line
			local phone = Board.layout(237, 112, Card.GLYPH)
			t.expect(phone.line).toBe(Board.MIN_LINE_PX)
			t.expect(phone.canvas > phone.view).toBe(true)
			t.expect(phone.view).toBeNear(112 - Board.TAB_PX - 2 * Board.MIN_LINE_PX, 1e-9)
			t.expect(Board.MIN_LINE_PX).toBe(13)
			t.expect(Board.MAX_LINE_PX).toBe(28)
		end
	)

	it("a slot of no size, or a size that is not finite, lays out at the smallest line", function()
		for _, h in { 0, -5, 0 / 0, math.huge } do
			local l = Board.layout(h, h, Card.GLYPH)
			t.expect(l.line).toBe(Board.MIN_LINE_PX)
			t.expect(l.view).toBe(0)
			t.expect(l.text).toBe(0)
		end
		-- a glyph width that is not a positive number counts a character as wide as the text is tall
		t.expect(Board.layout(290, 400, 0 / 0).text).toBe(10)
		t.expect(Board.layout(290, 400, -1).text).toBe(10)
	end)

	it(
		"every text on the front card's board is at least Card.MIN_TEXT pixels, whole, with a gap, on every screen",
		function()
			t.expect(Board.MIN_LINE_PX >= Card.MIN_TEXT).toBe(true)
			for _, s in SCREENS do
				local w, h = slot(s[1], s[2])
				local l = Board.layout(w, h, Card.GLYPH)
				local at = `{s[1]} x {s[2]}`
				t.expect(l.text >= Card.MIN_TEXT and at).toBe(at)
				t.expect(l.text == math.floor(l.text) and l.text <= l.line).toBe(true)
				-- each column's widest text, whole on one line at that size (Card's model)
				for _, c in Board.COLUMNS do
					for _, text in WIDEST[c.name] do
						t.expect(Card.textSize(text, c.width * w, l.line, false) >= l.text and at).toBe(at)
					end
				end
				-- between two labels, at least GUTTER characters at that size
				for i = 2, #Board.COLUMNS do
					local before, c = Board.COLUMNS[i - 1], Board.COLUMNS[i]
					t.expect((c.x - before.x - before.width) * w >= Board.GUTTER * Card.GLYPH * l.text - 1e-9)
						.toBe(true)
				end
				-- YOUR BEST from the rank's left edge to the name's right one
				local rank, named = Board.COLUMNS[1], Board.COLUMNS[2]
				local span = (named.x + named.width - rank.x) * w
				t.expect(Card.textSize(Board.BEST, span, l.line, false) >= l.text).toBe(true)
				-- each tab's word in a third of the slot, the tab bar tall
				for _, id in Board.TABS do
					t.expect(Card.textSize(Board.TAB_TEXT[id], w / 3, Board.TAB_PX, false) >= l.text)
						.toBe(true)
				end
				-- the notes, wrapped over two lines
				for _, note in { Board.LOADING, Board.EMPTY, Board.DOWN } do
					t.expect(Card.textSize(note, w, 2 * l.line, true) >= l.text).toBe(true)
				end
			end
		end
	)

	it(
		"the client asks for every card's board on the chosen tab, and the all-time one while its best is unknown",
		function()
			local names = { "pickman", "snake", "invaders", "asteroids" }
			local function keys(list: { Board.Want }): string
				local out = {}
				for _, w in list do
					table.insert(out, `{w.name}:{w.id}`)
				end
				return table.concat(out, " ")
			end
			t.expect(keys(Board.wants("all", names, {})))
				.toBe("pickman:all snake:all invaders:all asteroids:all")
			local mine: { [string]: Board.Mine } =
				{ pickman = KNOWN, snake = NONE, invaders = { known = false, best = nil } }
			t.expect(keys(Board.wants("day", names, mine)))
				.toBe("pickman:day snake:day invaders:day invaders:all asteroids:day asteroids:all")
			t.expect(keys(Board.wants("week", names, mine)))
				.toBe("pickman:week snake:week invaders:week invaders:all asteroids:week asteroids:all")
		end
	)

	it(
		"each board is asked for at once, then again after REASK, or WAIT_RETRY after a wait or a pending best",
		function()
			t.expect(Board.REASK).toBe(30)
			t.expect(Board.WAIT_RETRY).toBe(2)
			t.expect(Board.askDue(nil, 5)).toBe(true)
			local last: Board.Asked = { at = 100, wait = false }
			t.expect(Board.askDue(last, 100)).toBe(false)
			t.expect(Board.askDue(last, 129.9)).toBe(false)
			t.expect(Board.askDue(last, 130)).toBe(true)
			local waited: Board.Asked = { at = 100, wait = true }
			t.expect(Board.askDue(waited, 101.9)).toBe(false)
			t.expect(Board.askDue(waited, 102)).toBe(true)
		end
	)

	it("a clock that went back asks again; a time that is not finite asks nothing", function()
		local last: Board.Asked = { at = 100, wait = false }
		t.expect(Board.askDue(last, 99)).toBe(true)
		t.expect(Board.askDue(last, 0 / 0)).toBe(false)
		t.expect(Board.askDue(nil, math.huge)).toBe(false)
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
