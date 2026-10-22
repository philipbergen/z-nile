--!strict
-- Maze behaviours beyond the acceptance specs.
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

return t.spec("Maze extras", function(it)
	local m = Maze.parse({ "#####", "#P.o#", "#####" })

	it("neighbor returns a fresh table on every call", function()
		local a = Maze.neighbor(m, { x = 1, y = 1 }, "E")
		local b = Maze.neighbor(m, { x = 1, y = 1 }, "E")
		t.expect(a == b).toBe(false)
		a.x = 99
		t.expect(b.x).toBe(2)
	end)

	it("tiles of a kind that is absent is an empty list", function()
		t.expect(Maze.tiles(m, "door")).toEqual({})
	end)

	it("parse rejects non-string rows", function()
		local bad = { "#####", 5 :: any, "#####" }
		t.expect(function()
			Maze.parse(bad :: any)
		end).toThrow("row 1")
	end)

	it("a vertical tunnel reports its exits across the edge", function()
		local shaft = Maze.parse({ "#.#", "#P#", "#.#" })
		t.expect(Maze.exits(shaft, { x = 1, y = 0 }, "player")).toEqual({ "N", "S" })
	end)

	it("kind rejects fractional tiles", function()
		t.expect(function()
			Maze.kind(m, { x = 1.5, y = 1 })
		end).toThrow("bounds")
	end)
end)
