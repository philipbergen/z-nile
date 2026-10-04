--!strict
-- Ghosts: API cases beyond the acceptance specs.
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

return t.spec("Ghosts extras", function(it)
	it("the classic maze has four ghosts in the documented order", function()
		local set = Ghosts.new(classic, 1)
		t.expect(#set.ghosts).toBe(4)
		t.expect(Ghosts.NAMES).toEqual({ "blinky", "pinky", "inky", "clyde" })
		t.expect(Ghosts.available(classic)).toBe(true)
	end)

	it("a walker occupies the nearer centre and its position is the tile plus the progress", function()
		local w = Ghosts.walker({ x = 6, y = 5 }, "E")
		w.progress = 40
		t.expect(Ghosts.occupied(w)).toEqual({ x = 6, y = 5 })
		local x, y = Ghosts.position(w)
		t.expect(x).toBeNear(6 + 40 / 120, 1e-12)
		t.expect(y).toBe(5)
		w.progress = 70
		t.expect(Ghosts.occupied(w)).toEqual({ x = 7, y = 5 })
	end)

	it("the tunnel tiles are the six at each edge of the row that wraps, and nowhere else", function()
		for x = 0, 5 do
			t.expect(Ghosts.tunnel(classic, { x = x, y = 14 })).toBe(true)
			t.expect(Ghosts.tunnel(classic, { x = 27 - x, y = 14 })).toBe(true)
		end
		t.expect(Ghosts.tunnel(classic, { x = 6, y = 14 })).toBe(false)
		t.expect(Ghosts.tunnel(classic, { x = 2, y = 5 })).toBe(false)
	end)

	it("the occupied tiles of a set are always inside the grid, also half way through a wrap", function()
		local set = Ghosts.new(classic, 1, { start = "active" })
		local clyde = Ghosts.ghost(set, "clyde")
		clyde.tile, clyde.heading, clyde.progress = { x = 27, y = 14 }, "E", 70
		for _, tile in Ghosts.occupiedTiles(set) do
			t.expect(tile.x >= 0 and tile.x < classic.width).toBe(true)
			t.expect(tile.y >= 0 and tile.y < classic.height).toBe(true)
		end
		t.expect(Ghosts.occupiedTiles(set)[4]).toEqual({ x = 0, y = 14 })
	end)

	it("a set that is not frightened looks normal and does not flash", function()
		local set = Ghosts.new(classic, 1)
		t.expect(Ghosts.look(set, Ghosts.ghost(set, "blinky"))).toBe("normal")
		t.expect(Ghosts.flash(set)).toBe(false)
	end)

	it("the same seed gives the same wandering, a second set is independent of the first", function()
		local function trail(seed: number): string
			local set = Ghosts.new(classic, seed, { start = "active" })
			Ghosts.power(set, 300)
			local out = {}
			for _ = 1, 120 do
				Ghosts.step(
					set,
					{ player = { x = 1, y = 1 }, heading = "E", level = 1, baseSpeed = 30, tickRate = 30 }
				)
				table.insert(out, `{Ghosts.ghost(set, "pinky").tile.x},{Ghosts.ghost(set, "pinky").tile.y}`)
			end
			return table.concat(out, ";")
		end
		local a = trail(7)
		local _ = trail(8)
		t.expect(trail(7)).toBe(a)
	end)

	it("a ghost that leaves the house comes out heading west", function()
		local set = Ghosts.new(classic, 1)
		local input = {
			player = { x = 1, y = 29 },
			heading = "E" :: Maze.Heading,
			level = 3,
			baseSpeed = 30,
			tickRate = 30,
		}
		local left = false
		for _ = 1, 120 do
			for _, e in Ghosts.step(set, input) do
				if e.kind == "GhostLeft" and e.ghost == "pinky" then
					left = true
					t.expect(Ghosts.ghost(set, "pinky").heading).toBe("W")
				end
			end
		end
		t.expect(left).toBe(true)
	end)
end)
