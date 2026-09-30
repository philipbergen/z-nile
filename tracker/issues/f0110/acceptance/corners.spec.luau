--!strict
-- f0110 AC2: classic corners. With no turn buffered the player stops at a corner; a buffered turn
-- whose exit exists there is taken without stopping.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- Corridor east from the spawn to a corner at (5,1) that turns south into a dead end at (5,3).
local CORNER = { "#######", "#P....#", "#####.#", "#####.#", "#######" }

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

return t.spec("f0110 corners", function(it)
	it("stops at a corner when no turn is buffered", function()
		local trace = sim.run(model(CORNER, "E", CFG), {
			seed = 1,
			ticks = 30,
			script = {
				sim.expect(16, { x = 5, y = 1, heading = "E", moving = false }),
				sim.expect(30, { x = 5, y = 1, heading = "E", moving = false }),
			},
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(16)
	end)

	it("takes a buffered turn at the corner without stopping", function()
		local trace = sim.run(model(CORNER, "E", CFG), {
			seed = 1,
			ticks = 30,
			script = {
				sim.intent(10, "Right"),
				sim.expect(16, { x = 5, y = 1, heading = "S", moving = true }),
				sim.expect(17, { x = 5, y = 1.25, heading = "S" }),
				sim.expect(24, { x = 5, y = 3, moving = false }),
			},
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(24)
	end)

	it("ignores a buffered turn whose exit does not exist at the corner", function()
		local trace = sim.run(model(CORNER, "E", CFG), {
			seed = 1,
			ticks = 30,
			script = {
				sim.intent(10, "Left"),
				sim.expect(16, { x = 5, y = 1, heading = "E", moving = false }),
				sim.expect(30, { x = 5, y = 1, heading = "E", moving = false }),
			},
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(16)
	end)

	it("carries the step's remaining distance around the corner", function()
		sim.run(model(CORNER, "E", { speed = 45, turnBufferTicks = 24 }), {
			seed = 1,
			ticks = 12,
			script = {
				sim.intent(0, "Right"),
				sim.expect(10, { x = 4.75, y = 1, heading = "E" }),
				sim.expect(11, { x = 5, y = 1.125, heading = "S", moving = true }),
			},
		})
	end)
end)
