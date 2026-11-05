--!strict
-- Ghosts: the maze a step walks (f0126's picked holes).
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

return t.spec("Ghosts maze", function(it)
	it("useMaze takes an opened copy of the set's maze", function()
		local set = Ghosts.new(classic, 1)
		local copy = Maze.open(classic, { x = 2, y = 2 })
		Ghosts.useMaze(set, copy)
		t.expect(set.maze).toBe(copy)
	end)

	it("useMaze refuses a maze of another id or size", function()
		local set = Ghosts.new(classic, 1)
		local other = Maze.parse({ "#####", "#P..#", "#####" })
		t.expect(function()
			Ghosts.useMaze(set, other)
		end).toThrow("is not a copy")
	end)
end)
