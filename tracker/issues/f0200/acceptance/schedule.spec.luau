--!strict
-- f0200: the ghosts alternate scatter and chase on the level's timetable, every active ghost turns back at the
-- next centre when the mode changes (and never otherwise), and each mode has its own target. Ghosts start active
-- here: the house is f0210.
local Ghosts = require("@logic/Ghosts")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")

local function input(level: number?, player: Maze.Tile?): Ghosts.Input
	return {
		player = player or { x = 1, y = 1 },
		heading = "E",
		level = level or 1,
		baseSpeed = 30,
		tickRate = 30,
	}
end

local function newSet(seed: number?, level: number?): Ghosts.Set
	return Ghosts.new(classic, seed or 1, { start = "active", level = level })
end

local function run(set: Ghosts.Set, ticks: number, level: number?): { Ghosts.Event }
	local all: { Ghosts.Event } = {}
	for _ = 1, ticks do
		for _, e in Ghosts.step(set, input(level)) do
			table.insert(all, e)
		end
	end
	return all
end

local function modeChanges(events: { Ghosts.Event }): { string }
	local out = {}
	for _, e in events do
		if e.kind == "ModeChanged" then
			table.insert(out, tostring(e.mode))
		end
	end
	return out
end

-- a ghost standing mid-corridor on the open row 5 (all ghosts), progress 0, heading east
local function inCorridor(set: Ghosts.Set)
	for i, g in set.ghosts do
		g.tile = { x = 3 + i * 4, y = 5 }
		g.heading = "E"
		g.progress = 0
	end
end

return t.spec("f0200 scatter and chase", function(it)
	it("starts in scatter and changes mode exactly when each phase of the level's timetable ends", function()
		local set = newSet()
		t.expect(set.mode).toBe("scatter")
		run(set, 209)
		t.expect(set.mode).toBe("scatter")
		local events = run(set, 1) -- the 210th tick ends the 7 s of scatter
		t.expect(modeChanges(events)).toEqual({ "chase" })
		t.expect(set.mode).toBe("chase")
	end)
	it(
		"follows level 1's timetable: scatter 7, chase 20, scatter 7, chase 20, scatter 5, chase 20, scatter 5, then chase for good",
		function()
			local set = newSet()
			local all = run(set, 210 + 600 + 210 + 600 + 150 + 600 + 150 + 5000)
			t.expect(modeChanges(all))
				.toEqual({ "chase", "scatter", "chase", "scatter", "chase", "scatter", "chase" })
			t.expect(set.mode).toBe("chase")
		end
	)
	it("uses the timetable of the level it is told, and level 5's starts with 5 s of scatter", function()
		local set = newSet(1, 5)
		run(set, 149, 5)
		t.expect(set.mode).toBe("scatter")
		run(set, 1, 5)
		t.expect(set.mode).toBe("chase")
	end)
	it(
		"every active ghost turns back at its next tile centre when the mode changes, and not before",
		function()
			local set = newSet()
			inCorridor(set)
			run(set, 205)
			-- park every ghost mid-tile heading east on row 5, then let the change happen
			for _, g in set.ghosts do
				g.tile, g.heading, g.progress, g.reverse = { x = 5, y = 5 }, "E", 60, false
			end
			set.phaseTicks = 209
			local events = run(set, 1)
			t.expect(modeChanges(events)).toEqual({ "chase" })
			for _, g in set.ghosts do
				t.expect(g.reverse).toBe(true)
				t.expect(g.heading).toBe("E") -- still going on to the centre
			end
			run(set, 3)
			for _, g in set.ghosts do
				t.expect(g.reverse).toBe(false)
				t.expect(g.heading).toBe("W") -- turned back at the centre of tile 6
			end
		end
	)
	it("never reverses by itself while the mode stays the same", function()
		for seed = 1, 5 do
			local set = newSet(seed)
			local last: { [string]: Maze.Heading } = {}
			local reversals = 0
			for _ = 1, 205 do
				Ghosts.step(set, input(1, { x = 3 + seed, y = 20 }))
				for _, g in set.ghosts do
					local before: Maze.Heading? = last[g.name]
					if before and g.heading == Maze.opposite(before) then
						reversals += 1
					end
					last[g.name] = g.heading
				end
			end
			t.expect(reversals).toBe(0)
		end
	end)
	it("hunting ghosts head for their scatter corner in scatter and for the chase target in chase", function()
		local set = newSet()
		-- Blinky in scatter at a junction picks the exit toward (25,-3)
		local blinky = Ghosts.ghost(set, "blinky")
		blinky.tile, blinky.heading, blinky.progress = { x = 6, y = 5 }, "E", 0
		Ghosts.step(set, input())
		t.expect(blinky.heading).toBe("E")
		-- in chase with the player far to the south it goes south instead
		set.mode = "chase"
		blinky.tile, blinky.heading, blinky.progress, blinky.reverse = { x = 6, y = 5 }, "E", 0, false
		Ghosts.step(set, input(1, { x = 1, y = 29 }))
		t.expect(blinky.heading).toBe("S")
	end)
	it("a new level or a reset starts the timetable again at scatter", function()
		local set = newSet()
		run(set, 400)
		t.expect(set.mode).toBe("chase")
		Ghosts.reset(set, "level", 2)
		t.expect(set.mode).toBe("scatter")
		t.expect(set.phase).toBe(1)
		t.expect(set.phaseTicks).toBe(0)
		t.expect(set.level).toBe(2)
		t.expect(set.frightened).toBe(0)
	end)
end)
