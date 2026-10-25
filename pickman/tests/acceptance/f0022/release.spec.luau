--!strict
-- f0210: who starts inside the house and when each ghost leaves: personal pellet counters, the idle timer, the
-- global counter after a death, and the Levels columns behind them.
local Ghosts = require("@logic/Ghosts")
local Levels = require("@logic/Levels")
local Maze = require("@logic/Maze")
local t = require("@tests/lib/t")

local classic = Maze.layout("classic")
local WAITERS: { Ghosts.Name } = { "pinky", "inky", "clyde" }

local function input(level: number?): Ghosts.Input
	return { player = { x = 1, y = 29 }, heading = "E", level = level or 1, baseSpeed = 30, tickRate = 30 }
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

local function released(events: { Ghosts.Event }): { string }
	local out = {}
	for _, e in events do
		if e.kind == "GhostReleased" then
			table.insert(out, tostring(e.ghost))
		end
	end
	return out
end

local function eatPellets(set: Ghosts.Set, n: number): { string }
	local out = {}
	for _ = 1, n do
		for _, e in Ghosts.pelletEaten(set) do
			if e.kind == "GhostReleased" then
				table.insert(out, tostring(e.ghost))
			end
		end
	end
	return out
end

local function status(set: Ghosts.Set, name: Ghosts.Name): string
	return Ghosts.ghost(set, name).status
end

return t.spec("f0210 releasing from the house", function(it)
	it("Blinky starts active above the door; the other three start waiting inside the house", function()
		local set = Ghosts.new(classic, 1)
		local blinky = Ghosts.ghost(set, "blinky")
		t.expect(blinky.status).toBe("active")
		t.expect(blinky.tile).toEqual({ x = 14, y = 11 })
		t.expect(blinky.heading).toBe("W")
		for name, tile in
			{ pinky = { x = 13, y = 14 }, inky = { x = 12, y = 14 }, clyde = { x = 15, y = 14 } }
		do
			local g = Ghosts.ghost(set, name :: Ghosts.Name)
			t.expect(g.status).toBe("house")
			t.expect(g.tile).toEqual(tile)
			t.expect(Maze.kind(classic, g.tile)).toBe("house")
		end
	end)
	it("a ghost waiting in the house does not move", function()
		local set = Ghosts.new(classic, 1)
		Ghosts.step(set, input()) -- pinky is released at once, the others are not
		local inky = Ghosts.ghost(set, "inky")
		local tile, progress = { x = inky.tile.x, y = inky.tile.y }, inky.progress
		eatPellets(set, 3)
		run(set, 20)
		t.expect(inky.tile).toEqual(tile)
		t.expect(inky.progress).toBe(progress)
	end)
	it("the door and the house are for ghosts only: the player cannot enter either", function()
		for _, tile in Maze.tiles(classic, "door") do
			t.expect(Maze.passable(classic, tile, "player")).toBe(false)
			t.expect(Maze.passable(classic, tile, "ghost")).toBe(true)
		end
		t.expect(Maze.passable(classic, { x = 13, y = 14 }, "player")).toBe(false)
	end)
	it(
		"level 1 releases Pinky at once, Inky after 30 pellets and Clyde after 60 more, counting only for the ghost next in line",
		function()
			local set = Ghosts.new(classic, 1)
			-- before the first step Pinky is next in line: its limit is 0, so the first pellet releases it
			t.expect(eatPellets(set, 1)).toEqual({ "pinky" })
			t.expect(status(set, "pinky")).toBe("leaving")
			-- that pellet counted for Pinky only: Inky still needs 30 of its own
			t.expect(eatPellets(set, 29)).toEqual({})
			t.expect(status(set, "inky")).toBe("house")
			t.expect(eatPellets(set, 1)).toEqual({ "inky" })
			-- Clyde needs 60 of its own
			t.expect(eatPellets(set, 59)).toEqual({})
			t.expect(status(set, "clyde")).toBe("house")
			t.expect(eatPellets(set, 1)).toEqual({ "clyde" })
		end
	)
	it("a limit of 0 releases the ghost at the first step, without any pellet", function()
		local set = Ghosts.new(classic, 1)
		local events = run(set, 1)
		t.expect(released(events)).toEqual({ "pinky" })
		t.expect(status(set, "inky")).toBe("house")
	end)
	it(
		"level 2 releases Inky straight after Pinky and Clyde after 50 pellets; level 3 and later release all three at once",
		function()
			local l2 = Ghosts.new(classic, 1, { level = 2 })
			t.expect(released(run(l2, 1, 2))).toEqual({ "pinky", "inky" })
			t.expect(eatPellets(l2, 49)).toEqual({})
			t.expect(eatPellets(l2, 1)).toEqual({ "clyde" })
			local l3 = Ghosts.new(classic, 1, { level = 3 })
			t.expect(released(run(l3, 1, 3))).toEqual({ "pinky", "inky", "clyde" })
		end
	)
	it("the Levels table holds the personal limits and the idle timer", function()
		t.expect(Levels.row(1).dotLimits).toEqual({ pinky = 0, inky = 30, clyde = 60 })
		t.expect(Levels.row(2).dotLimits).toEqual({ pinky = 0, inky = 0, clyde = 50 })
		t.expect(Levels.row(3).dotLimits).toEqual({ pinky = 0, inky = 0, clyde = 0 })
		t.expect(Levels.row(40).dotLimits).toEqual({ pinky = 0, inky = 0, clyde = 0 })
		for level = 1, 4 do
			t.expect(Levels.row(level).idleSeconds).toBe(4)
		end
		t.expect(Levels.row(5).idleSeconds).toBe(3)
		t.expect(Levels.row(21).idleSeconds).toBe(3)
	end)
	it(
		"with no pellet eaten for 4 s (3 s from level 5) the next ghost in line leaves, and a pellet restarts the wait",
		function()
			local set = Ghosts.new(classic, 1)
			run(set, 1) -- Pinky out
			t.expect(released(run(set, 118))).toEqual({})
			t.expect(status(set, "inky")).toBe("house")
			eatPellets(set, 1) -- the wait starts again
			t.expect(released(run(set, 119))).toEqual({})
			t.expect(released(run(set, 1))).toEqual({ "inky" })
			-- level 5 waits 3 s = 90 ticks: after a death (the global counter is on, so nobody leaves at once)
			local l5 = Ghosts.new(classic, 1, { level = 5 })
			Ghosts.reset(l5, "respawn", 5)
			t.expect(released(run(l5, 89, 5))).toEqual({})
			t.expect(released(run(l5, 1, 5))).toEqual({ "pinky" })
			local l1 = Ghosts.new(classic, 1)
			Ghosts.reset(l1, "respawn", 1)
			t.expect(released(run(l1, 119))).toEqual({})
			t.expect(released(run(l1, 1))).toEqual({ "pinky" })
		end
	)
	it(
		"after a death the house counts with one global counter: Pinky at 7 pellets, Inky at 17, Clyde at 32",
		function()
			local set = Ghosts.new(classic, 1)
			run(set, 1)
			eatPellets(set, 100) -- Inky and Clyde are out and about
			Ghosts.reset(set, "respawn", 1)
			for _, name: Ghosts.Name in WAITERS do
				t.expect(status(set, name)).toBe("house")
			end
			t.expect(set.house.global).toBe(0)
			-- no release at the first step any more: Pinky waits for its 7 pellets
			t.expect(released(run(set, 1))).toEqual({})
			t.expect(eatPellets(set, 6)).toEqual({})
			t.expect(eatPellets(set, 1)).toEqual({ "pinky" })
			t.expect(eatPellets(set, 9)).toEqual({})
			t.expect(eatPellets(set, 1)).toEqual({ "inky" })
			t.expect(eatPellets(set, 14)).toEqual({})
			t.expect(eatPellets(set, 1)).toEqual({ "clyde" })
			-- with Clyde out the personal counters are back in charge
			t.expect(set.house.global).toBe(nil)
		end
	)
	it("a new level or a new run clears the counters and the global mode", function()
		local set = Ghosts.new(classic, 1)
		run(set, 1)
		eatPellets(set, 20)
		Ghosts.reset(set, "respawn", 1)
		Ghosts.reset(set, "level", 2)
		t.expect(set.house.global).toBe(nil)
		t.expect(set.house.personal).toEqual({ pinky = 0, inky = 0, clyde = 0 })
		t.expect(set.level).toBe(2)
		Ghosts.reset(set, "run", 1)
		t.expect(set.level).toBe(1)
		t.expect(status(set, "inky")).toBe("house")
	end)
	it("a death keeps the personal counters", function()
		local set = Ghosts.new(classic, 1)
		run(set, 1)
		eatPellets(set, 12)
		Ghosts.reset(set, "respawn", 1)
		t.expect(set.house.personal.inky).toBe(12)
	end)
end)
