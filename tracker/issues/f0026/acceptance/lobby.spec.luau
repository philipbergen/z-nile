--!strict
-- f0026 AC1: the existing panel stays the all-time board. Day and week are a pure switch on top of it.
-- Lobby.panel and MAX_ROWS do not change.
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local board = (Lobby :: any).board
local boardTitle = (Lobby :: any).boardTitle
local boardPanel = (Lobby :: any).boardPanel
local lines = (Lobby :: any).lines

local function row(rank: number, name: string, score: number, level: number): any
	return { rank = rank, name = name, score = score, level = level }
end

return t.spec("f0026 lobby boards", function(it)
	it("the panel constants and the empty cap stay", function()
		t.expect(Lobby.TITLE).toBe("HISCORES")
		t.expect(Lobby.EMPTY).toBe("No scores yet")
		t.expect(Lobby.MAX_ROWS).toBe(10)
		t.expect(Lobby.BUTTON_MIN_PX).toBe(44)
		t.expect((Lobby :: any).READ_GAP).toBe(1)
		local many = {}
		for i = 1, 11 do
			table.insert(many, row(i, "P", i, 1))
		end
		t.expect(#Lobby.panel(many).rows).toBe(10)
		local empty = Lobby.panel(nil)
		t.expect(empty.title).toBe("HISCORES")
		t.expect(empty.empty).toBe("No scores yet")
		t.expect(empty.rows).toEqual({})
	end)

	it("a client score does not switch the board", function()
		t.expect(board("all")).toBe("all")
		t.expect(board("day")).toBe("day")
		t.expect(board("week")).toBe("week")
		t.expect(board("ALL")).toBe(nil)
		t.expect(board("nope")).toBe(nil)
		t.expect(board({ score = 99999 })).toBe(nil)
		t.expect(board(5000)).toBe(nil)
		t.expect(board(nil)).toBe(nil)
	end)

	it("all-time keeps the hiscores title, and day and week name themselves", function()
		t.expect(boardTitle("all")).toBe("HISCORES")
		t.expect(boardTitle(nil)).toBe("HISCORES")
		t.expect(boardTitle("nope")).toBe("HISCORES")
		t.expect(boardTitle("day")).toBe("TODAY")
		t.expect(boardTitle("week")).toBe("THIS WEEK")
		local today = boardPanel(nil, "day")
		t.expect(today.title).toBe("TODAY")
		t.expect(today.empty).toBe("No scores yet")
		local all = boardPanel({ row(1, "A", 10, 2) }, "all")
		t.expect(all.title).toBe("HISCORES")
		t.expect(all.empty).toBe(nil)
		t.expect(all.rows[1].name).toBe("A")
		t.expect(all.rows[1].score).toBe(10)
		local week = boardPanel({ row(1, "B", 4, 3) }, "week")
		t.expect(week.title).toBe("THIS WEEK")
		local capped = {}
		for i = 1, 11 do
			table.insert(capped, row(i, "P", i, 1))
		end
		t.expect(#boardPanel(capped, "day").rows).toBe(10)
	end)

	it("the highlight is a rank, not the first row, and an empty panel keeps its message", function()
		local text = lines({
			empty = nil,
			rows = { row(1, "A", 10, 2), row(2, "B", 9, 4) },
		}, 2)
		t.expect(text).toBe("1 A 10 2\n> 2 B 9 4")
		t.expect(lines({ empty = "No scores yet", rows = {} }, nil)).toBe("No scores yet")
		t.expect(lines({ empty = "No scores yet", rows = {} }, 1)).toBe("No scores yet")
	end)
end)
