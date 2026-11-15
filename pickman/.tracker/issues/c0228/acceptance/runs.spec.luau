--!strict
-- c0228 AC1: View.runsKey, the key MazeView keeps of the walls it has drawn. Equal walls give equal keys, however the
-- maze and the marks were made (fresh tables, the marks in another order); walls that differ in any run's bounds or
-- in whether it is marked give different keys, so a rewall to other walls is never skipped.
local Maze = require("@logic/Maze")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

local function at(x: number, y: number): Maze.Tile
	return { x = x, y = y }
end

local function key(m: Maze.Maze, marked: { Maze.Tile }?): string
	return View.runsKey(View.walls(m, nil, marked))
end

-- a wall tile that is a run of one tile in classic's walls (unmarked), so marking it keeps the run's bounds
local function lone(): Maze.Tile
	for _, r in View.walls(classic) do
		if r.x0 == r.x1 and r.x0 >= 0 and r.x0 < classic.width and r.y0 >= 0 and r.y0 < classic.height then
			return at(r.x0, r.y0)
		end
	end
	error("classic has no one-tile wall run")
end

return t.spec("c0228 View.runsKey", function(it)
	it("equal walls give equal keys: fresh mazes and marks, the marks in another order", function()
		local marks = { at(2, 2), at(7, 2), at(25, 6) }
		t.expect(key(classic, marks)).toBe(key(classic, { at(25, 6), at(2, 2), at(7, 2) }))
		local holes = { at(2, 2), at(14, 10) }
		local a = Maze.opened(classic, holes)
		local b = Maze.opened(Maze.layout("classic"), { at(14, 10), at(2, 2) })
		t.expect(a ~= b).toBe(true) -- two tables: the key compares values, not identity
		t.expect(key(a, { at(7, 2) })).toBe(key(b, { at(7, 2) }))
		t.expect(key(classic)).toBe(key(classic, {}))
	end)

	it("walls with a moved mark, a mark more or less, or another hole give other keys", function()
		local base = key(classic, { at(2, 2), at(7, 2) })
		t.expect(key(classic, { at(3, 2), at(7, 2) }) ~= base).toBe(true) -- a mark moved
		t.expect(key(classic, { at(2, 2) }) ~= base).toBe(true) -- a mark less
		t.expect(key(classic) ~= base).toBe(true) -- no marks
		t.expect(key(Maze.opened(classic, { at(14, 10) }), { at(2, 2), at(7, 2) }) ~= base).toBe(true) -- a hole
	end)

	it("a one-tile run marked or not gives another key, though its bounds stay the same", function()
		local tile = lone()
		t.expect(key(classic, { tile }) ~= key(classic)).toBe(true)
	end)

	it(
		"runs that differ in any bound or in the mark give other keys; unmarked is unmarked either way",
		function()
			local base = { x0 = 1, y0 = 2, x1 = 3, y1 = 2 }
			local k = View.runsKey({ base })
			local variants: { View.Rect } = {
				{ x0 = 0, y0 = 2, x1 = 3, y1 = 2 },
				{ x0 = 1, y0 = 3, x1 = 3, y1 = 2 },
				{ x0 = 1, y0 = 2, x1 = 4, y1 = 2 },
				{ x0 = 1, y0 = 2, x1 = 3, y1 = 3 },
				{ x0 = 1, y0 = 2, x1 = 3, y1 = 2, marked = true },
			}
			local seen: { [string]: boolean } = { [k] = true }
			for _, v in variants do
				local vk = View.runsKey({ v })
				t.expect(seen[vk]).toBe(nil)
				seen[vk] = true
			end
			t.expect(View.runsKey({ { x0 = 1, y0 = 2, x1 = 3, y1 = 2, marked = false } })).toBe(k)
			-- the runs together: one more, one less, none
			local two = View.runsKey({ base, variants[3] })
			t.expect(two ~= k).toBe(true)
			t.expect(View.runsKey({}) ~= k).toBe(true)
			t.expect(View.runsKey({ variants[3] }) ~= two).toBe(true)
			-- the bounds kept apart: (1, 23) and (12, 3) are other runs, however their digits run together
			t.expect(View.runsKey({ { x0 = 1, y0 = 23, x1 = 4, y1 = 23 } }) ~= View.runsKey({
				{ x0 = 12, y0 = 3, x1 = 4, y1 = 23 },
			})).toBe(true)
		end
	)
end)
