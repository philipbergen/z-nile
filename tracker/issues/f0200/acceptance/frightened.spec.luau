--!strict
-- f0200: a power pellet turns the ghosts blue: they turn back once, then wander at random (seeded), slower, the
-- timetable stops, they blink before they recover, and the end comes after exactly the level's ticks.
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

-- a ghost standing mid-corridor on the open row 5 (all ghosts), progress 0, heading east
local function inCorridor(set: Ghosts.Set)
	for i, g in set.ghosts do
		g.tile = { x = 3 + i * 4, y = 5 }
		g.heading = "E"
		g.progress = 0
	end
end

return t.spec("f0200 frightened mode", function(it)
	it("a power pellet turns every ghost blue, resets the eaten chain, and starts the countdown", function()
		local set = newSet()
		set.chain = 3
		Ghosts.power(set, 180)
		t.expect(set.frightened).toBe(180)
		t.expect(set.chain).toBe(0)
		for _, g in set.ghosts do
			t.expect(g.frightened).toBe(true)
			t.expect(Ghosts.look(set, g)).toBe("frightened")
		end
	end)
	it(
		"frightened ghosts turn back once at the next centre, then move at random without turning back",
		function()
			local set = newSet(3)
			for _, g in set.ghosts do
				g.tile, g.heading, g.progress = { x = 5, y = 5 }, "E", 110 -- 10 units short of the next centre
			end
			Ghosts.power(set, 600)
			for _, g in set.ghosts do
				t.expect(g.reverse).toBe(true)
			end
			Ghosts.step(set, input()) -- 110 + 19 units: past the centre of tile 6
			for _, g in set.ghosts do
				t.expect(g.reverse).toBe(false)
				t.expect(g.heading).toBe("W")
			end
			local last: { [string]: Maze.Heading } = {}
			local reversals, turns = 0, 0
			for _ = 1, 400 do
				Ghosts.step(set, input())
				for _, g in set.ghosts do
					local before: Maze.Heading? = last[g.name]
					if before and g.heading ~= before then
						turns += 1
						if g.heading == Maze.opposite(before) then
							reversals += 1
						end
					end
					last[g.name] = g.heading
				end
			end
			t.expect(turns > 10).toBe(true) -- they do wander
			t.expect(reversals).toBe(0)
		end
	)
	it("random movement is seeded: the same seed walks the same way, another seed does not", function()
		local function trail(seed: number): string
			local set = newSet(seed)
			Ghosts.power(set, 600)
			local out = {}
			for _ = 1, 400 do
				Ghosts.step(set, input())
				for _, g in set.ghosts do
					table.insert(out, `{g.tile.x},{g.tile.y}`)
				end
			end
			return table.concat(out, ";")
		end
		t.expect(trail(5)).toBe(trail(5))
		t.expect(trail(5) ~= trail(6)).toBe(true)
	end)
	it(
		"a frightened ghost moves at the frightened speed, a hunting one faster, and either is slower in a tunnel",
		function()
			local set = newSet()
			inCorridor(set)
			local blinky = Ghosts.ghost(set, "blinky")
			Ghosts.step(set, input())
			t.expect(blinky.progress).toBe(28) -- level 1, hunting
			inCorridor(set)
			Ghosts.power(set, 400)
			for _, g in set.ghosts do
				g.reverse = false
			end
			Ghosts.step(set, input())
			t.expect(blinky.progress).toBe(19) -- frightened
			-- in the side tunnel, row 14 at the west edge
			for _, g in set.ghosts do
				g.frightened, g.tile, g.heading, g.progress = false, { x = 3, y = 14 }, "W", 0
			end
			Ghosts.step(set, input())
			t.expect(blinky.progress).toBe(15)
		end
	)
	it(
		"a blue ghost in a tunnel moves at the tunnel speed, which is slower than the frightened speed",
		function()
			local set = newSet()
			Ghosts.power(set, 400)
			for _, g in set.ghosts do
				g.reverse, g.tile, g.heading, g.progress = false, { x = 3, y = 14 }, "W", 0
			end
			Ghosts.step(set, input())
			t.expect(Ghosts.ghost(set, "blinky").progress).toBe(15) -- not the 19 of a blue ghost in the open
		end
	)

	it("the speeds follow the level and the tuning factor", function()
		local set = Ghosts.new(classic, 1, { start = "active", level = 5, tuning = 0.5 })
		inCorridor(set)
		Ghosts.step(set, input(5))
		t.expect(Ghosts.ghost(set, "blinky").progress).toBe(18) -- round(30 * 1.1875 * 0.5) = round(17.8)
	end)
	it("the timetable clock stops while the ghosts are blue, and runs on afterwards", function()
		local set = newSet()
		run(set, 100)
		local before = set.phaseTicks
		Ghosts.power(set, 50)
		run(set, 50)
		t.expect(set.phaseTicks).toBe(before)
		t.expect(set.frightened).toBe(0)
		run(set, 10)
		t.expect(set.phaseTicks).toBe(before + 10)
	end)
	it("frightened mode ends after exactly the level's ticks and says so", function()
		local set = newSet()
		Ghosts.power(set, 30)
		local events = run(set, 29)
		t.expect(#events == 0 or events[#events].kind ~= "FrightenedEnded").toBe(true)
		for _, g in set.ghosts do
			t.expect(g.frightened).toBe(true)
		end
		local last = run(set, 1)
		local ended = false
		for _, e in last do
			if e.kind == "FrightenedEnded" then
				ended = true
			end
		end
		t.expect(ended).toBe(true)
		for _, g in set.ghosts do
			t.expect(g.frightened).toBe(false)
			t.expect(Ghosts.look(set, g)).toBe("normal")
		end
	end)
	it("the ghosts blink for the last `flashes` flashes of 14 ticks of the countdown, not before", function()
		local set = newSet() -- level 1: 5 flashes = the last 70 ticks
		Ghosts.power(set, 180)
		local ghost = Ghosts.ghost(set, "blinky")
		run(set, 109)
		t.expect(set.frightened).toBe(71)
		t.expect(Ghosts.look(set, ghost)).toBe("frightened")
		run(set, 1)
		t.expect(set.frightened).toBe(70)
		t.expect(Ghosts.look(set, ghost)).toBe("blinking")
		-- a level with 3 flashes blinks for 42 ticks only
		local short = newSet(1, 9)
		Ghosts.power(short, 100)
		short.frightened = 43
		t.expect(Ghosts.look(short, Ghosts.ghost(short, "blinky"))).toBe("frightened")
		short.frightened = 42
		t.expect(Ghosts.look(short, Ghosts.ghost(short, "blinky"))).toBe("blinking")
	end)
	it(
		"while blinking the flash alternates blue and white every 7 ticks, starting blue, and is false at any other time",
		function()
			local set = newSet()
			t.expect(Ghosts.flash(set)).toBe(false) -- not frightened
			Ghosts.power(set, 180)
			t.expect(Ghosts.flash(set)).toBe(false) -- not yet blinking
			local seen = {}
			for left = 70, 1, -1 do
				set.frightened = left
				table.insert(seen, if Ghosts.flash(set) then "w" else "b")
			end
			t.expect(table.concat(seen)).toBe(string.rep(string.rep("b", 7) .. string.rep("w", 7), 5))
		end
	)
	it(
		"a power pellet where the level has no frightened time still turns the ghosts back, but not blue",
		function()
			local set = newSet(1, 17)
			Ghosts.power(set, 0)
			for _, g in set.ghosts do
				t.expect(g.frightened).toBe(false)
				t.expect(g.reverse).toBe(true)
			end
			t.expect(set.frightened).toBe(0)
		end
	)
	it(
		"no ghost turns back when the blue time ends: a power pellet reverses them, its end does not",
		function()
			local set = newSet(2)
			inCorridor(set)
			Ghosts.power(set, 40)
			for _, g in set.ghosts do
				g.reverse = false -- the turn-back at the start is not what is being looked at
			end
			local last: { [string]: Maze.Heading } = {}
			local reversals = 0
			for _ = 1, 200 do
				Ghosts.step(set, input())
				for _, g in set.ghosts do
					local before: Maze.Heading? = last[g.name]
					if before and g.heading == Maze.opposite(before) then
						reversals += 1
					end
					last[g.name] = g.heading
				end
			end
			t.expect(set.frightened).toBe(0)
			t.expect(reversals).toBe(0)
			for _, g in set.ghosts do
				t.expect(g.reverse).toBe(false)
			end
		end
	)

	it("a second power pellet starts the countdown over, and eyes are not made blue again", function()
		local set = newSet()
		Ghosts.power(set, 100)
		run(set, 60)
		Ghosts.ghost(set, "inky").status = "eyes"
		Ghosts.ghost(set, "inky").frightened = false
		Ghosts.power(set, 100)
		t.expect(set.frightened).toBe(100)
		t.expect(Ghosts.ghost(set, "inky").frightened).toBe(false)
		t.expect(Ghosts.ghost(set, "blinky").frightened).toBe(true)
	end)
end)
