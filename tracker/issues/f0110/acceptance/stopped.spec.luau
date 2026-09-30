--!strict
-- f0110 AC4: a stopped player turns in the same step when the exit exists; otherwise nothing moves.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- The player stops at the corner (5,1) at tick 16, facing east; the only way on is south.
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

local function run(script: { sim.Item })
	return sim.run(model(CORNER, "E", CFG), { seed = 1, ticks = 40, script = script })
end

return t.spec("f0110 turning from a stop", function(it)
	it("a turn whose exit exists applies in the step it arrives and restarts movement", function()
		run({
			sim.expect(20, { x = 5, y = 1, moving = false }),
			sim.intent(20, "Right"),
			sim.expect(21, { x = 5, y = 1.25, heading = "S", moving = true }),
		})
	end)

	it("a turn toward a wall leaves the player stopped and facing the same way", function()
		run({
			sim.intent(20, "Left"),
			sim.expect(21, { x = 5, y = 1, heading = "E", moving = false }),
			sim.expect(40, { x = 5, y = 1, heading = "E", moving = false }),
		})
	end)

	it("Forward does not restart a stopped player", function()
		run({
			sim.intent(20, "Forward"),
			sim.expect(21, { x = 5, y = 1, heading = "E", moving = false }),
		})
	end)

	it("the latest of several intents in one tick decides the turn", function()
		run({
			sim.intent(20, "Left"),
			sim.intent(20, "Right"),
			sim.expect(21, { x = 5, y = 1.25, heading = "S", moving = true }),
		})
	end)
end)
