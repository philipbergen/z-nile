--!strict
-- f0100 AC1: parse builds a maze whose queries match the text, in the documented coordinates.
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

-- x = column, y = row, both 0-based from the top-left character.
local ROWS = {
	"#####", -- y = 0
	"#P.o#", -- y = 1: spawn (1,1), pellet (2,1), power (3,1)
	"# # #", -- y = 2: empty (1,2) and (3,2)
	" .-H ", -- y = 3: tunnel ends (0,3)/(4,3), pellet (1,3), door (2,3), house (3,3)
	"#####", -- y = 4
}

local function tile(x: number, y: number): Maze.Tile
	return { x = x, y = y }
end

return t.spec("f0100 Maze.parse and queries", function(it)
	local m = Maze.parse(ROWS)

	it("reports size, spawn and id", function()
		t.expect(m.width).toBe(5)
		t.expect(m.height).toBe(5)
		t.expect(m.spawn).toEqual({ x = 1, y = 1 })
		t.expect(m.id).toBe("custom")
		t.expect(Maze.parse(ROWS, "tiny").id).toBe("tiny")
	end)

	it("kind follows the character at column x, row y", function()
		t.expect(Maze.kind(m, tile(0, 0))).toBe("wall")
		t.expect(Maze.kind(m, tile(1, 1))).toBe("spawn")
		t.expect(Maze.kind(m, tile(2, 1))).toBe("pellet")
		t.expect(Maze.kind(m, tile(3, 1))).toBe("power")
		t.expect(Maze.kind(m, tile(1, 2))).toBe("empty")
		t.expect(Maze.kind(m, tile(2, 2))).toBe("wall")
		t.expect(Maze.kind(m, tile(0, 3))).toBe("empty")
		t.expect(Maze.kind(m, tile(1, 3))).toBe("pellet")
		t.expect(Maze.kind(m, tile(2, 3))).toBe("door")
		t.expect(Maze.kind(m, tile(3, 3))).toBe("house")
	end)

	it("kind outside the grid is an error, not a wall", function()
		t.expect(function()
			Maze.kind(m, tile(5, 1))
		end).toThrow("bounds")
		t.expect(function()
			Maze.kind(m, tile(-1, 1))
		end).toThrow("bounds")
		t.expect(function()
			Maze.kind(m, tile(1, 5))
		end).toThrow("bounds")
	end)

	it("passable depends on the agent: doors and the house are ghost-only", function()
		local cases: { { number | string | boolean } } = {
			{ 0, 0, false, false },
			{ 1, 1, true, true },
			{ 2, 1, true, true },
			{ 3, 1, true, true },
			{ 1, 2, true, true },
			{ 2, 3, false, true },
			{ 3, 3, false, true },
		}
		for _, c in cases do
			local x, y = c[1] :: number, c[2] :: number
			t.expect(Maze.passable(m, tile(x, y), "player")).toBe(c[3])
			t.expect(Maze.passable(m, tile(x, y), "ghost")).toBe(c[4])
		end
	end)

	it("neighbor steps one tile and wraps at the edges", function()
		local n, w = Maze.neighbor(m, tile(1, 1), "N")
		t.expect(n).toEqual({ x = 1, y = 0 })
		t.expect(w).toBe(false)
		n, w = Maze.neighbor(m, tile(1, 1), "E")
		t.expect(n).toEqual({ x = 2, y = 1 })
		t.expect(w).toBe(false)
		n, w = Maze.neighbor(m, tile(1, 1), "S")
		t.expect(n).toEqual({ x = 1, y = 2 })
		n, w = Maze.neighbor(m, tile(0, 3), "W")
		t.expect(n).toEqual({ x = 4, y = 3 })
		t.expect(w).toBe(true)
		n, w = Maze.neighbor(m, tile(4, 3), "E")
		t.expect(n).toEqual({ x = 0, y = 3 })
		t.expect(w).toBe(true)
		n, w = Maze.neighbor(m, tile(2, 0), "N")
		t.expect(n).toEqual({ x = 2, y = 4 })
		t.expect(w).toBe(true)
	end)

	it("exits lists passable headings in N, E, S, W order, per agent", function()
		t.expect(Maze.exits(m, tile(1, 1), "player")).toEqual({ "E", "S" })
		t.expect(Maze.exits(m, tile(3, 2), "player")).toEqual({ "N" })
		t.expect(Maze.exits(m, tile(3, 2), "ghost")).toEqual({ "N", "S" })
		t.expect(Maze.exits(m, tile(0, 3), "player")).toEqual({ "E", "W" })
		t.expect(Maze.exits(m, tile(1, 3), "player")).toEqual({ "N", "W" })
		t.expect(Maze.exits(m, tile(1, 3), "ghost")).toEqual({ "N", "E", "W" })
	end)

	it("isJunction means more than two exits for that agent", function()
		t.expect(Maze.isJunction(m, tile(1, 3), "player")).toBe(false)
		t.expect(Maze.isJunction(m, tile(1, 3), "ghost")).toBe(true)
		t.expect(Maze.isJunction(m, tile(1, 1), "player")).toBe(false)
	end)

	it("tiles lists every tile of a kind in row-major order", function()
		t.expect(Maze.tiles(m, "pellet")).toEqual({ { x = 2, y = 1 }, { x = 1, y = 3 } })
		t.expect(Maze.tiles(m, "power")).toEqual({ { x = 3, y = 1 } })
		t.expect(Maze.tiles(m, "door")).toEqual({ { x = 2, y = 3 } })
		t.expect(Maze.tiles(m, "house")).toEqual({ { x = 3, y = 3 } })
		t.expect(Maze.tiles(m, "spawn")).toEqual({ { x = 1, y = 1 } })
		t.expect(Maze.tiles(m, "empty"))
			.toEqual({ { x = 1, y = 2 }, { x = 3, y = 2 }, { x = 0, y = 3 }, { x = 4, y = 3 } })
		t.expect(#Maze.tiles(m, "wall")).toBe(15)
	end)

	it("a parsed maze is read-only", function()
		t.expect(function()
			(m :: any).width = 9
		end).toThrow()
		t.expect(function()
			(m.spawn :: any).x = 3
		end).toThrow()
		t.expect(Maze.kind(m, tile(1, 1))).toBe("spawn")
	end)

	it("layout returns a built-in maze, the same one on every call", function()
		local a = Maze.layout("classic")
		t.expect(a.id).toBe("classic")
		t.expect(Maze.layout("classic") == a).toBe(true)
		t.expect(function()
			Maze.layout("nope")
		end).toThrow("unknown layout")
	end)
end)
