--!strict
-- f0190: walking the rails: whole units per tick, one decision at every centre, tunnels, and the properties that
-- must hold however a ghost is steered (never in a wall, door or house, never turning back by itself, deterministic).
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

return t.spec("f0190 ghost walking", function(it)
	it("walks the given number of units along its rails and reports the tiles it enters", function()
		local w = Ghosts.walker({ x = 6, y = 23 }, "N")
		local seen = 0
		local decisions = 0
		for _ = 1, 8 do
			for _, e in
				Ghosts.walk(classic, w, 30, function(_tile: Maze.Tile, heading: Maze.Heading): Maze.Heading
					decisions += 1
					return heading
				end)
			do
				if e.kind == "Entered" then
					seen += 1
				end
			end
		end
		-- 8 ticks of 30 units = 240 units = 2 tiles; one decision at each centre including the start
		t.expect(w.tile).toEqual({ x = 6, y = 21 })
		t.expect(w.progress).toBe(0)
		t.expect(seen).toBe(2)
		t.expect(decisions).toBe(2)
	end)
	it("decides exactly once at every centre, however the speed divides the tile", function()
		for _, speed in { 7, 28, 30, 45, 120 } do
			local w = Ghosts.walker({ x = 6, y = 23 }, "N")
			local decisions, units = 0, 0
			for _ = 1, 40 do
				Ghosts.walk(classic, w, speed, function(_tile: Maze.Tile, heading: Maze.Heading): Maze.Heading
					decisions += 1
					return heading
				end)
				units += speed
			end
			-- one decision per centre reached or standing on, counting the start
			t.expect(decisions).toBe(math.floor((units - 1) / Movement.UNITS) + 1)
		end
	end)
	it("wraps through a tunnel and says so", function()
		local w = Ghosts.walker({ x = 1, y = 14 }, "W")
		local wrapped = 0
		for _ = 1, 12 do
			for _, e in
				Ghosts.walk(classic, w, 30, function(_tile: Maze.Tile, heading: Maze.Heading): Maze.Heading
					return heading
				end)
			do
				if e.kind == "Wrapped" then
					wrapped += 1
				end
			end
		end
		t.expect(wrapped).toBe(1)
		t.expect(w.tile.x > 20).toBe(true)
	end)
	it(
		"a hunting ghost never stands on a wall, in the door or the house, and never reverses by itself",
		function()
			-- four ghosts from four starts on the open row 5, 20 seeds of changing targets, 2500 ticks each
			local starts: { Maze.Tile } =
				{ { x = 3, y = 5 }, { x = 8, y = 5 }, { x = 14, y = 5 }, { x = 20, y = 5 } }
			local reversals, bad = 0, 0
			for seed = 1, 20 do
				for i, start in starts do
					local startHeading: Maze.Heading = if i % 2 == 0 then "E" else "W"
					local w = Ghosts.walker(start, startHeading)
					for tick = 1, 2500 do
						local target = {
							x = (seed * 7 + tick // 90 * (3 + i)) % 28,
							y = (seed * 5 + tick // 70 * (2 + i)) % 31,
						}
						Ghosts.walk(
							classic,
							w,
							28,
							function(tile: Maze.Tile, heading: Maze.Heading): Maze.Heading
								local picked: Maze.Heading =
									Ghosts.pickExit(classic, tile, heading, target, { noUp = true })
								local back: Maze.Heading = Maze.opposite(heading)
								if picked == back then
									reversals += 1
								end
								return picked
							end
						)
						local o = Ghosts.occupied(w)
						local tile = { x = o.x % classic.width, y = o.y % classic.height }
						local kind = Maze.kind(classic, tile)
						if kind == "wall" or kind == "door" or kind == "house" then
							bad += 1
						end
					end
				end
			end
			t.expect(bad).toBe(0)
			t.expect(reversals).toBe(0)
		end
	)
	it("the same decisions give the same walk", function()
		local function run(): string
			local w = Ghosts.walker({ x = 14, y = 11 }, "W")
			local trail = {}
			for tick = 1, 500 do
				Ghosts.walk(classic, w, 28, function(tile: Maze.Tile, heading: Maze.Heading): Maze.Heading
					return Ghosts.pickExit(classic, tile, heading, { x = tick % 28, y = 20 }, { noUp = true })
				end)
				table.insert(trail, `{w.tile.x},{w.tile.y},{w.progress}`)
			end
			return table.concat(trail, ";")
		end
		t.expect(run()).toBe(run())
	end)
end)
