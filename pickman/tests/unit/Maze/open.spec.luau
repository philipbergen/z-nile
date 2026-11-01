--!strict
-- Maze: a copy with walls opened (f0126).
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

return t.spec("Maze open", function(it)
	local m = Maze.parse({ "######", "#P...#", "#.##.#", "#....#", "######" })

	it("opening two walls in turn opens both, and the copy is frozen", function()
		local o = Maze.opened(m, { { x = 2, y = 2 }, { x = 3, y = 2 } })
		t.expect(Maze.kind(o, { x = 2, y = 2 })).toBe("empty")
		t.expect(Maze.kind(o, { x = 3, y = 2 })).toBe("empty")
		t.expect(Maze.kind(m, { x = 2, y = 2 })).toBe("wall")
		t.expect(table.isfrozen(o)).toBe(true)
	end)

	it("opening the same wall twice refuses the second, which is no longer a wall", function()
		t.expect(function()
			Maze.opened(m, { { x = 2, y = 2 }, { x = 2, y = 2 } })
		end).toThrow("not a wall")
	end)
end)
