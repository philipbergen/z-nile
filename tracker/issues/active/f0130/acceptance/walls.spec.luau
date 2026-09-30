--!strict
-- f0130 AC1: View.walls turns the maze into merged horizontal wall runs, and repeats the maze
-- beyond each wrapping edge so a tunnel never looks like a dead end.
local Maze = require("@logic/Maze")
local View = require("@logic/View")
local t = require("@tests/lib/t")

type Rect = View.Rect

local function covered(rects: { Rect }): { [string]: number }
	local out: { [string]: number } = {}
	for _, r in rects do
		t.expect(r.y0).toBe(r.y1) -- one row per run
		t.expect(r.x0 <= r.x1).toBe(true)
		for x = r.x0, r.x1 do
			local k = `{x},{r.y0}`
			out[k] = (out[k] or 0) + 1
		end
	end
	return out
end

-- Every tile in the rendered range is covered exactly once if it is a wall (periodically, on the
-- wrapping axes) and not at all otherwise; nothing outside the range is covered.
local function checkCoverage(m: Maze.Maze, rects: { Rect }, mx: number, my: number)
	local cov = covered(rects)
	local count = 0
	for y = -my, m.height - 1 + my do
		for x = -mx, m.width - 1 + mx do
			local wall = Maze.kind(m, { x = x % m.width, y = y % m.height }) == "wall"
			local k = `{x},{y}`
			local n = cov[k] or 0
			if (wall and n ~= 1) or (not wall and n ~= 0) then
				error(`tile ({x}, {y}): wall = {wall}, covered {n} times`)
			end
			count += n
		end
	end
	local total = 0
	for _, n in cov do
		total += n
	end
	t.expect(total).toBe(count) -- nothing outside the range
end

-- Runs are maximal: two runs on the same row never touch.
local function checkMaximal(rects: { Rect })
	local byRow: { [number]: { Rect } } = {}
	for _, r in rects do
		byRow[r.y0] = byRow[r.y0] or {}
		table.insert(byRow[r.y0], r)
	end
	for y, row in byRow do
		table.sort(row, function(a: Rect, b: Rect)
			return a.x0 < b.x0
		end)
		for i = 2, #row do
			if row[i].x0 <= row[i - 1].x1 + 1 then
				error(`row {y}: runs {row[i - 1].x0}..{row[i - 1].x1} and {row[i].x0}..{row[i].x1} touch`)
			end
		end
	end
end

return t.spec("f0130 wall geometry", function(it)
	it("covers the classic maze with maximal runs, repeated 12 tiles beyond the tunnel edges", function()
		local m = Maze.layout("classic")
		-- row 14's first walls are 11 tiles in from each edge, so a 12-tile margin shows the far wall
		t.expect(View.TUNNEL_MARGIN).toBe(12)
		local rects = View.walls(m)
		checkCoverage(m, rects, 12, 0)
		checkMaximal(rects)
	end)

	it("merging keeps the part count well under the wall-tile count", function()
		local m = Maze.layout("classic")
		local rects = View.walls(m)
		local tiles = 0
		for _, r in rects do
			tiles += r.x1 - r.x0 + 1
		end
		t.expect(#rects * 4 < tiles).toBe(true)
	end)

	it("bounds is the rendered tile range: the margin applies only on wrapping axes", function()
		t.expect(View.bounds(Maze.layout("classic"))).toEqual({ x0 = -12, y0 = 0, x1 = 39, y1 = 30 })
		t.expect(View.bounds(Maze.parse({ "#.#", "#P#", "#.#" }), 2))
			.toEqual({ x0 = 0, y0 = -2, x1 = 2, y1 = 4 })
		t.expect(View.bounds(Maze.parse({ "#####", "#P. #", "#####" }), 3))
			.toEqual({ x0 = 0, y0 = 0, x1 = 4, y1 = 2 })
		t.expect(View.bounds(Maze.parse({ "#####", " P.  ", "#####" }), 2))
			.toEqual({ x0 = -2, y0 = 0, x1 = 6, y1 = 2 })
	end)

	it("adds no margin to a maze without tunnels", function()
		local m = Maze.parse({ "#####", "#P. #", "#####" })
		local rects = View.walls(m, 3)
		checkCoverage(m, rects, 0, 0)
		checkMaximal(rects)
	end)

	it("honours an explicit margin and applies it only to the wrapping axis", function()
		local horizontal = Maze.parse({ "#####", " P.  ", "#####" })
		checkCoverage(horizontal, View.walls(horizontal, 2), 2, 0)
		local vertical = Maze.parse({ "#.#", "#P#", "#.#" })
		local rects = View.walls(vertical, 2)
		checkCoverage(vertical, rects, 0, 2)
		checkMaximal(rects)
	end)

	it("never covers doors, the house or corridors", function()
		local m = Maze.layout("classic")
		local cov = covered(View.walls(m))
		for _, kind: Maze.Kind in { "door", "house", "pellet", "power", "empty", "spawn" } :: { Maze.Kind } do
			for _, tile in Maze.tiles(m, kind) do
				t.expect(cov[`{tile.x},{tile.y}`]).toBe(nil)
			end
		end
	end)
end)
