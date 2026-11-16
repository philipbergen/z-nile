--!strict
-- f0126 AC2: Maze.open and Maze.opened, the picked hole: a copy of the maze with one wall tile empty, the same id,
-- size and spawn (so the ghost data and the pellet slots still apply), the original untouched; never an edge wall.
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local CORRIDOR = Maze.parse({ "#########", "#########", "#.....P.#", "#########", "#########" }, "corridor")

local function at(x: number, y: number): Maze.Tile
	return { x = x, y = y }
end

return t.spec("f0126 Maze.open", function(it)
	it("Maze.open makes one wall empty in a copy: same id, size and spawn, the original untouched", function()
		local opened = Maze.open(CORRIDOR, at(3, 1))
		t.expect(opened ~= CORRIDOR).toBe(true)
		t.expect(opened.id).toBe("corridor")
		t.expect(opened.width).toBe(CORRIDOR.width)
		t.expect(opened.height).toBe(CORRIDOR.height)
		t.expect(opened.spawn.x).toBe(CORRIDOR.spawn.x)
		t.expect(Maze.kind(opened, at(3, 1))).toBe("empty")
		t.expect(Maze.passable(opened, at(3, 1), "player")).toBe(true)
		t.expect(Maze.kind(CORRIDOR, at(3, 1))).toBe("wall")
		for y = 0, 4 do
			for x = 0, 8 do
				if not (x == 3 and y == 1) then
					t.expect(Maze.kind(opened, at(x, y))).toBe(Maze.kind(CORRIDOR, at(x, y)))
				end
			end
		end
	end)

	it("Maze.open refuses a tile that is not a wall, and a wall on the edge", function()
		t.expect(function()
			Maze.open(CORRIDOR, at(3, 2))
		end).toThrow("not a wall")
		t.expect(function()
			Maze.open(CORRIDOR, at(0, 2))
		end).toThrow("edge")
		t.expect(function()
			Maze.open(CORRIDOR, at(4, 4))
		end).toThrow("edge")
	end)

	it("Maze.opened opens every tile in turn, and with none it is the maze itself", function()
		t.expect(Maze.opened(CORRIDOR, {})).toBe(CORRIDOR)
		local m = Maze.opened(CORRIDOR, { at(3, 1), at(3, 3) })
		t.expect(Maze.kind(m, at(3, 1))).toBe("empty")
		t.expect(Maze.kind(m, at(3, 3))).toBe("empty")
		t.expect(Maze.kind(m, at(4, 1))).toBe("wall")
	end)
end)
