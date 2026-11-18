--!strict
-- d0124 AC5 (pure part): the all-time panel ends with the viewer's own best, "YOUR BEST <score> <level>", from what
-- the server sent; other boards, and a viewer with no best, show the panel's lines as f0026 draws them. Narrowed by
-- c0380: the rows and the best line are pinned up to the level, and the best line ends as a row of the same figures.
local Lobby = require("@logic/Lobby")
local t = require("@tests/lib/t")

local L = Lobby :: any

-- c0380: what follows the level changes (f0145's lives, then f0186's revives), so a board's lines are pinned up to
-- the level: each line of `text` that is the line `want` has there, or starts with it and a space, is cut back to it;
-- every other line, and the number of lines, stay as they are, so a compare with `want` still shows them.
local function upToLevel(text: any, want: string): any
	if type(text) ~= "string" then
		return text
	end
	local got, keep = string.split(text, "\n"), string.split(want, "\n")
	for i, line in got do
		local w = keep[i]
		if w ~= nil and (line == w or string.sub(line, 1, #w + 1) == w .. " ") then
			got[i] = w
		end
	end
	return table.concat(got, "\n")
end

local rows = {
	{ rank = 1, name = "Bea", score = 80, level = 3 },
	{ rank = 2, name = "Ada", score = 50, level = 2 },
}

return t.spec("d0124 your best", function(it)
	it("the best line starts with the score and the level, on the all-time board only", function()
		t.expect(upToLevel(L.bestLine({ score = 50, level = 2 }, "all"), "YOUR BEST 50 2"))
			.toBe("YOUR BEST 50 2")
		t.expect(upToLevel(L.bestLine({ score = 0, level = 1 }, "all"), "YOUR BEST 0 1"))
			.toBe("YOUR BEST 0 1")
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
		local text = L.text(panel, 2, { score = 50, level = 2 }, "all")
		t.expect(text).toBe(Lobby.lines(panel, 2) .. "\n" .. L.bestLine({ score = 50, level = 2 }, "all"))
		t.expect(upToLevel(text, "1 Bea 80 3\n> 2 Ada 50 2\nYOUR BEST 50 2"))
			.toBe("1 Bea 80 3\n> 2 Ada 50 2\nYOUR BEST 50 2")
		-- the best line ends as the row of the same score and level ends (nothing, or f0186's revives)
		local lines = string.split(text, "\n")
		t.expect(string.sub(lines[3], #"YOUR BEST 50 2" + 1)).toBe(string.sub(lines[2], #"> 2 Ada 50 2" + 1))
		t.expect(L.text(panel, 2, nil, "all")).toBe(Lobby.lines(panel, 2))
		local day = Lobby.boardPanel(rows, "day")
		t.expect(L.text(day, nil, { score = 50, level = 2 }, "day")).toBe(Lobby.lines(day, nil))
	end)

	it("an empty all-time board still shows the viewer's best under its message", function()
		local empty = Lobby.boardPanel({}, "all")
		local text = L.text(empty, nil, { score = 9, level = 1 }, "all")
		t.expect(text).toBe(Lobby.lines(empty, nil) .. "\n" .. L.bestLine({ score = 9, level = 1 }, "all"))
		t.expect(Lobby.lines(empty, nil)).toBe("No scores yet")
		t.expect(upToLevel(text, "No scores yet\nYOUR BEST 9 1")).toBe("No scores yet\nYOUR BEST 9 1")
	end)
end)
