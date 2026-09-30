--!strict
-- f0110 AC3: turn intents are buffered and taken at the next tile centre where that exit exists.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- An east-west corridor on row 2 from the spawn (1,2) to (7,2), with a north branch at (3,2)
-- and a south branch at (5,2).
local BRANCHES = {
	"#########",
	"###.#####",
	"#P......#",
	"#####.###",
	"#####.###",
	"#########",
}

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

local function run(script: { sim.Item }, config: Movement.Config?, ticks: number?)
	return sim.run(model(BRANCHES, "E", config or CFG), { seed = 1, ticks = ticks or 30, script = script })
end

return t.spec("f0110 buffered turns", function(it)
	it("passes a junction without the exit and turns at the first one with it", function()
		run({
			sim.intent(0, "Right"),
			sim.expect(8, { x = 3, y = 2, heading = "E" }),
			sim.expect(9, { x = 3.25, y = 2, heading = "E" }),
			sim.expect(16, { x = 5, y = 2, heading = "S", moving = true }),
			sim.expect(17, { x = 5, y = 2.25, heading = "S" }),
		})
	end)

	it("turns relative to the current heading: Left from east is north", function()
		run({
			sim.intent(0, "Left"),
			sim.expect(8, { x = 3, y = 2, heading = "N" }),
			sim.expect(9, { x = 3, y = 1.75, heading = "N" }),
		})
	end)

	it("a turn pressed while passing through a junction centre is taken there", function()
		-- at time 8 the player is on (3,2), still moving east: step 8 takes the turn from the centre
		run({
			sim.expect(8, { x = 3, y = 2, heading = "E", moving = true }),
			sim.intent(8, "Left"),
			sim.expect(9, { x = 3, y = 1.75, heading = "N", moving = true }),
		})
		run({
			sim.intent(16, "Right"),
			sim.expect(17, { x = 5, y = 2.25, heading = "S", moving = true }),
		})
	end)

	it("keeps only the latest Left or Right", function()
		run({
			sim.intent(0, "Left"),
			sim.intent(1, "Right"),
			sim.expect(9, { x = 3.25, y = 2, heading = "E" }),
			sim.expect(17, { x = 5, y = 2.25, heading = "S" }),
		})
	end)

	it("applies several intents in one tick in order", function()
		run({
			sim.intent(0, "Right"),
			sim.intent(0, "Forward"),
			sim.expect(17, { x = 5.25, y = 2, heading = "E" }),
		})
		run({
			sim.intent(0, "Forward"),
			sim.intent(0, "Right"),
			sim.expect(17, { x = 5, y = 2.25, heading = "S" }),
		})
	end)

	it("Forward clears the buffered turn, so the junction is passed straight", function()
		local trace = run({
			sim.intent(0, "Right"),
			sim.intent(2, "Forward"),
			sim.expect(17, { x = 5.25, y = 2, heading = "E" }),
			sim.expect(24, { x = 7, y = 2, moving = false }),
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(24)
	end)

	it("a turn stays pending for exactly turnBufferTicks steps, counting the one it arrives in", function()
		-- The player reaches (5,2) during step 15. With a window of 6, an intent at tick 10 is
		-- pending in steps 10..15 and is taken; one at tick 9 expired after step 14.
		local short = { speed = 30, turnBufferTicks = 6 }
		run({
			sim.intent(10, "Right"),
			sim.expect(16, { x = 5, y = 2, heading = "S" }),
			sim.expect(17, { x = 5, y = 2.25, heading = "S" }),
		}, short)
		run({
			sim.intent(9, "Right"),
			sim.expect(16, { x = 5, y = 2, heading = "E" }),
			sim.expect(17, { x = 5.25, y = 2, heading = "E" }),
		}, short)
	end)

	it("pressing the same turn again restarts its window", function()
		-- with a window of 6, a press at 9 alone expires after step 14; pressing again at 10 keeps it
		-- pending through step 15, when the player reaches (5,2)
		run({
			sim.intent(9, "Right"),
			sim.intent(10, "Right"),
			sim.expect(17, { x = 5, y = 2.25, heading = "S" }),
		}, { speed = 30, turnBufferTicks = 6 })
	end)
end)
