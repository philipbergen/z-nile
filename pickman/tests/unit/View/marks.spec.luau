--!strict
-- View: marked walls, the frame's maze and the walls key (f0126).
local Maze = require("@logic/Maze")
local View = require("@logic/View")
local t = require("@tests/lib/t")

return t.spec("View marks", function(it)
	it("a marked wall in the middle of a run splits it in three", function()
		local m = Maze.parse({ "#####", "#P..#", "#####" })
		local runs = View.walls(m, 0, { { x = 2, y = 0 } })
		local top = {}
		for _, r in runs do
			if r.y0 == 0 and r.y1 == 0 then
				table.insert(top, r)
			end
		end
		table.sort(top, function(a, b)
			return a.x0 < b.x0
		end)
		t.expect(#top).toBe(3)
		t.expect(top[2]).toEqual({ x0 = 2, y0 = 0, x1 = 2, y1 = 0, marked = true })
	end)

	it("a mark on a tile that is not a wall draws nothing extra", function()
		local m = Maze.parse({ "#####", "#P..#", "#####" })
		t.expect(View.walls(m, 0, { { x = 2, y = 1 } })).toEqual(View.walls(m, 0))
	end)

	it("the walls key tells holes apart from marks", function()
		local a =
			View.wallsKey({ maze = "classic", walls = { opened = { { x = 1, y = 2 } }, marked = {} } } :: any)
		local b =
			View.wallsKey({ maze = "classic", walls = { opened = {}, marked = { { x = 1, y = 2 } } } } :: any)
		t.expect(a == b).toBe(false)
	end)

	it("the frame's maze is cached for the same holes, and rebuilt for others", function()
		local f1 = { maze = "classic", walls = { opened = {}, marked = {} } } :: any
		local m1 = View.frameMaze(f1)
		t.expect(View.frameMaze(f1)).toBe(m1)
		t.expect(m1).toBe(Maze.layout("classic"))
	end)

	it("the gold wins over the edible green, and the flash over the gold", function()
		t.expect(View.wallColor(false, true, true)).toEqual(View.WALL_MARKED_COLOR)
		t.expect(View.wallColor(true, false, true)).toEqual(View.WHITE)
		t.expect(View.wallColor(false, false, nil)).toEqual(View.WALL_COLOR)
	end)
end)
