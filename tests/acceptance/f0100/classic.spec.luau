--!strict
-- f0100 AC3: the classic layout is the designed 28x31 map, tile for tile.
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

-- The design's layout, duplicated here on purpose: the spec pins every tile.
local ROWS = {
	"############################",
	"#............##............#",
	"#.####.#####.##.#####.####.#",
	"#o####.#####.##.#####.####o#",
	"#.####.#####.##.#####.####.#",
	"#..........................#",
	"#.####.##.########.##.####.#",
	"#.####.##.########.##.####.#",
	"#......##....##....##......#",
	"######.##### ## #####.######",
	"######.##### ## #####.######",
	"######.##          ##.######",
	"######.## ###--### ##.######",
	"######.## #HHHHHH# ##.######",
	"      .   #HHHHHH#   .      ",
	"######.## #HHHHHH# ##.######",
	"######.## ######## ##.######",
	"######.##          ##.######",
	"######.## ######## ##.######",
	"######.## ######## ##.######",
	"#............##............#",
	"#.####.#####.##.#####.####.#",
	"#.####.#####.##.#####.####.#",
	"#o..##.......P .......##..o#",
	"###.##.##.########.##.##.###",
	"###.##.##.########.##.##.###",
	"#......##....##....##......#",
	"#.##########.##.##########.#",
	"#.##########.##.##########.#",
	"#..........................#",
	"############################",
}
local KIND: { [string]: string } = {
	["#"] = "wall",
	[" "] = "empty",
	["."] = "pellet",
	["o"] = "power",
	["P"] = "spawn",
	["-"] = "door",
	["H"] = "house",
}

return t.spec("f0100 classic layout", function(it)
	local m = Maze.layout(Maze.DEFAULT)

	it("is the default layout and is 28 x 31", function()
		t.expect(Maze.DEFAULT).toBe("classic")
		t.expect(m.id).toBe("classic")
		t.expect(m.width).toBe(28)
		t.expect(m.height).toBe(31)
	end)

	it("matches the designed map tile for tile", function()
		for y, row in ROWS do
			for x = 1, #row do
				local want = KIND[string.sub(row, x, x)]
				local got = Maze.kind(m, { x = x - 1, y = y - 1 })
				if got ~= want then
					error(`tile ({x - 1}, {y - 1}): expected {want}, got {got}`)
				end
			end
		end
	end)

	it("has 240 pellets and 4 power pellets in the corners", function()
		t.expect(#Maze.tiles(m, "pellet")).toBe(240)
		t.expect(Maze.tiles(m, "power")).toEqual({
			{ x = 1, y = 3 },
			{ x = 26, y = 3 },
			{ x = 1, y = 23 },
			{ x = 26, y = 23 },
		})
	end)

	it("has the spawn below the house, a two-tile door and an 18-tile house", function()
		t.expect(m.spawn).toEqual({ x = 13, y = 23 })
		t.expect(Maze.exits(m, m.spawn, "player")).toEqual({ "E", "W" })
		t.expect(Maze.tiles(m, "door")).toEqual({ { x = 13, y = 12 }, { x = 14, y = 12 } })
		t.expect(#Maze.tiles(m, "house")).toBe(18)
	end)

	it("wraps through one tunnel on row 14, both ways", function()
		local n, w = Maze.neighbor(m, { x = 27, y = 14 }, "E")
		t.expect(n).toEqual({ x = 0, y = 14 })
		t.expect(w).toBe(true)
		n, w = Maze.neighbor(m, { x = 0, y = 14 }, "W")
		t.expect(n).toEqual({ x = 27, y = 14 })
		t.expect(w).toBe(true)
		local edges = 0
		for y = 0, m.height - 1 do
			for _, x in { 0, m.width - 1 } do
				if Maze.passable(m, { x = x, y = y }, "player") then
					edges += 1
					t.expect(y).toBe(14)
				end
			end
		end
		t.expect(edges).toBe(2)
	end)

	it("has no dead ends: every player tile has at least two exits", function()
		for y = 0, m.height - 1 do
			for x = 0, m.width - 1 do
				local tile = { x = x, y = y }
				if Maze.passable(m, tile, "player") and #Maze.exits(m, tile, "player") < 2 then
					error(`dead end at ({x}, {y})`)
				end
			end
		end
	end)
end)
