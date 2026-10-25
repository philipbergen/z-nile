--!strict
-- f0100 AC1: the Blaster feature. A seeded drop roll when a ghost is eaten (50%, at most 3 held), spending a shot,
-- the four fire intents, and the line a shot takes along the grid: the player's tile first, then every tile the
-- player could walk to in that heading, stopped by a wall, a door or the house, carried round a wrapping row once.
-- The first active target on that line is hit.
local Blaster = require("@logic/Blaster")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
-- a door below the player, the house below that; a wrapping row 2
local DOOR = Maze.parse({ "#####", "#P  #", "#-  #", "#H  #", "#####" }, "door")
local WRAP = Maze.parse({ "#####", "#P  #", "     ", "#####" }, "wrap")

local function at(x: number, y: number): Maze.Tile
	return { x = x, y = y }
end

local function list(tiles: { Maze.Tile }): string
	local out = {}
	for _, tile in tiles do
		table.insert(out, `{tile.x},{tile.y}`)
	end
	return table.concat(out, " ")
end

local function target(x: number, y: number, active: boolean?): Blaster.Target
	return { tile = at(x, y), active = active ~= false }
end

return t.spec("f0100 blaster", function(it)
	it("holds at most three shots and drops one on half the eaten ghosts", function()
		t.expect(Blaster.MAX_SHOTS).toBe(3)
		t.expect(Blaster.DROP_PERCENT).toBe(50)
		t.expect(Blaster.new(1).shots).toBe(0)
	end)

	it("a seed rolls the same drops every time, and different seeds roll differently", function()
		local function rolls(seed: number): string
			local b = Blaster.new(seed)
			local out = {}
			for _ = 1, 40 do
				local before = b.shots
				Blaster.drop(b)
				table.insert(out, if b.shots > before then "1" else "0")
				b.shots = 0
			end
			return table.concat(out)
		end
		t.expect(rolls(7)).toBe(rolls(7))
		t.expect(rolls(7) ~= rolls(8)).toBe(true)
		t.expect(rolls(123456789) ~= rolls(7)).toBe(true)
	end)

	it("about half of the rolls drop, for every seed tried", function()
		for _, seed in { 1, 2, 3, 42, 1234567, 987654321 } do
			local b = Blaster.new(seed)
			local drops = 0
			for _ = 1, 2000 do
				if Blaster.drop(b) then
					drops += 1
				end
				b.shots = 0
			end
			t.expect(drops >= 900 and drops <= 1100).toBe(true)
		end
	end)

	it("a drop says whether a shot was gained, and a drop while three are held is lost", function()
		local b = Blaster.new(5)
		local gained, rolled = 0, 0
		while b.shots < 3 do
			local before = b.shots
			local got = Blaster.drop(b)
			rolled += 1
			t.expect(got).toBe(b.shots == before + 1)
			if got then
				gained += 1
			end
			t.expect(rolled < 200).toBe(true)
		end
		t.expect(gained).toBe(3)
		for _ = 1, 50 do
			t.expect(Blaster.drop(b)).toBe(false)
			t.expect(b.shots).toBe(3)
		end
	end)

	it("the roll is made even when full: what drops does not depend on what is held", function()
		local full, empty = Blaster.new(11), Blaster.new(11)
		full.shots = 3
		for _ = 1, 30 do
			Blaster.drop(full)
			Blaster.drop(empty)
			empty.shots = 0
		end
		-- both generators moved the same way, so they agree on the next roll
		full.shots, empty.shots = 0, 0
		t.expect(Blaster.drop(full)).toBe(Blaster.drop(empty))
		t.expect(full.rng).toBe(empty.rng)
	end)

	it("spending takes one shot, and nothing when there is none", function()
		local b = Blaster.new(1)
		t.expect(Blaster.spend(b)).toBe(false)
		t.expect(b.shots).toBe(0)
		b.shots = 2
		t.expect(Blaster.spend(b)).toBe(true)
		t.expect(b.shots).toBe(1)
		t.expect(Blaster.spend(b)).toBe(true)
		t.expect(Blaster.spend(b)).toBe(false)
		t.expect(b.shots).toBe(0)
	end)

	it("a reset empties the blaster", function()
		local b = Blaster.new(1)
		b.shots = 3
		Blaster.reset(b)
		t.expect(b.shots).toBe(0)
	end)

	it("the four fire intents name a heading, and nothing else does", function()
		local all: { Maze.Heading } = { "N", "E", "S", "W" }
		local seen: { [string]: boolean } = {}
		for _, h: Maze.Heading in all do
			local wire = Blaster.intent(h)
			t.expect(type(wire)).toBe("string")
			t.expect(seen[wire]).toBe(nil)
			seen[wire] = true
			t.expect(Blaster.heading(wire)).toBe(h)
		end
		t.expect(Blaster.intent("N")).toBe("FireN")
		t.expect(Blaster.intent("W")).toBe("FireW")
		local bad: { any } = {
			"Fire",
			"fireN",
			"FIREN",
			"FireX",
			"FireNE",
			" FireN",
			"N",
			"Left",
			"",
			1,
			true,
			{ "FireN" },
			{ heading = "N" },
		}
		for _, v in bad do
			t.expect(Blaster.heading(v)).toBe(nil)
		end
		t.expect(Blaster.heading(nil)).toBe(nil)
	end)

	it("a shot's line starts on the player's tile and runs to the last open tile before a wall", function()
		-- classic row 23 is open from x = 6 to 21, walls at 5 and 22
		t.expect(list(Blaster.ray(classic, at(6, 23), "W"))).toBe("6,23")
		local east = Blaster.ray(classic, at(6, 23), "E")
		t.expect(#east).toBe(16)
		t.expect(list({ east[1], east[2], east[16] })).toBe("6,23 7,23 21,23")
		t.expect(list(Blaster.ray(classic, at(1, 29), "N"))).toBe("1,29 1,28 1,27 1,26")
	end)

	it("a door stops it, and the house beyond a door is out of reach", function()
		t.expect(list(Blaster.ray(DOOR, at(1, 1), "S"))).toBe("1,1")
		t.expect(Blaster.target(DOOR, at(1, 1), "S", { target(1, 2), target(1, 3) })).toBe(nil)
	end)

	it("a wrapping row carries it round once, without coming back to the player's tile", function()
		t.expect(list(Blaster.ray(WRAP, at(2, 2), "E"))).toBe("2,2 3,2 4,2 0,2 1,2")
		t.expect(list(Blaster.ray(WRAP, at(2, 2), "W"))).toBe("2,2 1,2 0,2 4,2 3,2")
		t.expect(Blaster.target(WRAP, at(2, 2), "E", { target(1, 2) })).toBe(1)
		-- classic's tunnel row 14 wraps too
		local tunnel = Blaster.ray(classic, at(6, 14), "W")
		t.expect(list({ tunnel[1], tunnel[7], tunnel[8] })).toBe("6,14 0,14 27,14")
	end)

	it("the nearest active target on the line is hit, by its index", function()
		local targets = { target(11, 23), target(9, 23), target(24, 23), target(9, 22) }
		t.expect(Blaster.target(classic, at(6, 23), "E", targets)).toBe(2)
		t.expect(Blaster.target(classic, at(6, 23), "W", targets)).toBe(nil)
		t.expect(Blaster.target(classic, at(9, 23), "E", targets)).toBe(2) -- its own tile comes first
		t.expect(Blaster.target(classic, at(10, 23), "E", targets)).toBe(1)
	end)

	it("a target beyond a wall is out of reach, even on the same row", function()
		t.expect(Blaster.target(classic, at(6, 23), "E", { target(24, 23) })).toBe(nil)
		t.expect(Blaster.target(classic, at(6, 23), "E", { target(21, 23) })).toBe(1)
	end)

	it("an inactive target neither is hit nor stops the shot", function()
		local targets = { target(8, 23, false), target(12, 23), target(7, 23, false) }
		t.expect(Blaster.target(classic, at(6, 23), "E", targets)).toBe(2)
		t.expect(Blaster.target(classic, at(6, 23), "E", { target(8, 23, false) })).toBe(nil)
	end)

	it("on one tile the lowest index is hit", function()
		local targets = { target(5, 5, false), target(12, 23), target(12, 23), target(12, 23) }
		t.expect(Blaster.target(classic, at(6, 23), "E", targets)).toBe(2)
	end)

	it("an empty list is a miss, and the line is a fresh list each time", function()
		t.expect(Blaster.target(classic, at(6, 23), "E", {})).toBe(nil)
		local a = Blaster.ray(classic, at(6, 23), "E")
		a[1].x = 99
		t.expect(Blaster.ray(classic, at(6, 23), "E")[1].x).toBe(6)
	end)
end)
