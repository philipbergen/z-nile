--!strict
-- d0124 AC5 (pure part): the all-time panel ends with the viewer's own best, "YOUR BEST <score> <level>", from what
-- the server sent; other boards, and a viewer with no best, show the panel's lines as f0026 draws them.
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local L = Lobby :: any

local rows = {
	{ rank = 1, name = "Bea", score = 80, level = 3 },
	{ rank = 2, name = "Ada", score = 50, level = 2 },
}

return t.spec("d0124 your best", function(it)
	it("the best line is the score and the level, on the all-time board only", function()
		t.expect(L.bestLine({ score = 50, level = 2 }, "all")).toBe("YOUR BEST 50 2")
		t.expect(L.bestLine({ score = 0, level = 1 }, "all")).toBe("YOUR BEST 0 1")
		t.expect(L.bestLine({ score = 50, level = 2 }, "day")).toBe(nil)
		t.expect(L.bestLine({ score = 50, level = 2 }, "week")).toBe(nil)
		t.expect(L.bestLine({ score = 50, level = 2 }, nil)).toBe(nil)
	end)

	it("no best, or a broken one, is no line", function()
		t.expect(L.bestLine(nil, "all")).toBe(nil)
		t.expect(L.bestLine(50, "all")).toBe(nil)
		t.expect(L.bestLine({ score = 50 }, "all")).toBe(nil)
		t.expect(L.bestLine({ score = -1, level = 2 }, "all")).toBe(nil)
		t.expect(L.bestLine({ score = 1.5, level = 2 }, "all")).toBe(nil)
		t.expect(L.bestLine({ score = 5, level = 0 }, "all")).toBe(nil)
		t.expect(L.bestLine({ score = math.huge, level = 2 }, "all")).toBe(nil)
	end)

	it("the list text is the panel's lines, then the best line", function()
		local panel = Lobby.boardPanel(rows, "all")
		t.expect(L.text(panel, 2, { score = 50, level = 2 }, "all"))
			.toBe("1 Bea 80 3\n> 2 Ada 50 2\nYOUR BEST 50 2")
		t.expect(L.text(panel, 2, nil, "all")).toBe(Lobby.lines(panel, 2))
		local day = Lobby.boardPanel(rows, "day")
		t.expect(L.text(day, nil, { score = 50, level = 2 }, "day")).toBe(Lobby.lines(day, nil))
	end)

	it("an empty all-time board still shows the viewer's best under its message", function()
		local empty = Lobby.boardPanel({}, "all")
		t.expect(L.text(empty, nil, { score = 9, level = 1 }, "all")).toBe("No scores yet\nYOUR BEST 9 1")
	end)
end)
