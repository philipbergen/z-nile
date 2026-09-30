--!strict
-- f0110 AC1: straight movement at the configured speed, tile entry at the half-tile, stop before a wall.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local CORRIDOR = { "##########", "#P.......#", "##########" }

local function model(
	rows: { string },
	heading: Maze.Heading?,
	config: Movement.Config
): sim.Model<Movement.State>
	local maze = Maze.parse(rows)
	return {
		name = "movement",
		tickRate = 30,
		new = function(_seed: number): Movement.State
			return Movement.spawn(maze, heading)
		end,
		step = function(s: Movement.State, intents: { any }, _k: number): { sim.Event }?
			return Movement.step(maze, s, intents, config) :: any
		end,
		observe = function(s: Movement.State): any
			local x, y = Movement.position(s)
			return { x = x, y = y, heading = s.heading, moving = s.moving }
		end,
	}
end

local CFG = { speed = 30, turnBufferTicks = 24 }

return t.spec("f0110 straight movement", function(it)
	it("uses 120 sub-tile units per tile", function()
		t.expect(Movement.UNITS).toBe(120)
	end)

	it("moves speed/UNITS tiles per tick along the corridor centreline", function()
		local trace = sim.run(model(CORRIDOR, "E", CFG), {
			seed = 1,
			ticks = 20,
			script = {
				sim.expect(0, { x = 1, y = 1, heading = "E", moving = true }),
				sim.expect(1, { x = 1.25, y = 1 }),
				sim.expect(2, { x = 1.5, y = 1 }),
				sim.expect(4, { x = 2, y = 1 }),
				sim.expect(20, { x = 6, y = 1, moving = true }),
			},
		})
		t.expect(trace.steps).toBe(20)
	end)

	it("stops at the centre of the last tile before a wall", function()
		local trace = sim.run(model(CORRIDOR, "E", CFG), {
			seed = 1,
			ticks = 40,
			script = {
				sim.expect(27, { x = 7.75, moving = true }),
				sim.expect(28, { x = 8, y = 1, moving = false }),
				sim.expect(40, { x = 8, y = 1, moving = false, heading = "E" }),
			},
		})
		local stops = sim.events(trace, "Stopped")
		t.expect(#stops).toBe(1)
		t.expect(stops[1].tick).toBe(28)
		t.expect(stops[1].event.x).toBe(8)
		t.expect(stops[1].event.y).toBe(1)
	end)

	it("enters a tile when crossing the half-tile boundary, once per tile", function()
		local trace = sim.run(model(CORRIDOR, "E", CFG), { seed = 1, ticks = 40 })
		local got = {}
		for _, e in sim.events(trace, "Entered") do
			table.insert(got, { e.tick, e.event.x, e.event.y })
		end
		t.expect(got).toEqual({
			{ 2, 2, 1 },
			{ 6, 3, 1 },
			{ 10, 4, 1 },
			{ 14, 5, 1 },
			{ 18, 6, 1 },
			{ 22, 7, 1 },
			{ 26, 8, 1 },
		})
	end)

	it("carries the remainder past tile centres when speed does not divide a tile", function()
		local trace = sim.run(model(CORRIDOR, "E", { speed = 45, turnBufferTicks = 24 }), {
			seed = 1,
			ticks = 25,
			script = {
				sim.expect(1, { x = 1.375 }),
				sim.expect(3, { x = 2.125 }),
				sim.expect(18, { x = 7.75, moving = true }),
				sim.expect(19, { x = 8, moving = false }),
				sim.expect(25, { x = 8 }),
			},
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(19)
	end)

	it("occupied is the tile containing the player's centre point", function()
		local maze = Maze.parse(CORRIDOR)
		local s = Movement.spawn(maze, "E")
		t.expect(Movement.occupied(maze, s)).toEqual({ x = 1, y = 1 })
		Movement.step(maze, s, {}, CFG)
		t.expect(Movement.occupied(maze, s)).toEqual({ x = 1, y = 1 })
		Movement.step(maze, s, {}, CFG)
		t.expect(Movement.occupied(maze, s)).toEqual({ x = 2, y = 1 })
	end)
end)
