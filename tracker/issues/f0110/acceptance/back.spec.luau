--!strict
-- f0110 AC5: Back reverses immediately, mid-tile, at a centre or from a stop, and clears the buffer.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local CORRIDOR = { "##########", "#P.......#", "##########" }
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

return t.spec("f0110 Back", function(it)
	it("reverses mid-tile in the same step, from the current position", function()
		local trace = sim.run(model(CORRIDOR, "E", CFG), {
			seed = 1,
			ticks = 20,
			script = {
				sim.expect(5, { x = 2.25, heading = "E" }),
				sim.intent(5, "Back"),
				sim.expect(6, { x = 2, heading = "W", moving = true }),
				sim.expect(10, { x = 1, moving = false }),
			},
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(10)
		local entered = {}
		for _, e in sim.events(trace, "Entered") do
			table.insert(entered, { e.tick, e.event.x })
		end
		t.expect(entered).toEqual({ { 2, 2 }, { 8, 1 } })
	end)

	it("reverses at a tile centre", function()
		sim.run(model(CORRIDOR, "E", CFG), {
			seed = 1,
			ticks = 6,
			script = {
				sim.expect(4, { x = 2 }),
				sim.intent(4, "Back"),
				sim.expect(5, { x = 1.75, heading = "W", moving = true }),
			},
		})
	end)

	it("restarts a player stopped at a wall, heading the other way", function()
		sim.run(model(CORRIDOR, "E", CFG), {
			seed = 1,
			ticks = 32,
			script = {
				sim.expect(30, { x = 8, moving = false }),
				sim.intent(30, "Back"),
				sim.expect(31, { x = 7.75, heading = "W", moving = true }),
			},
		})
	end)

	it("reverses the current heading literally, even right after a turn (arcade rule)", function()
		-- the player turns south at the corner (5,1) at time 16; Back then faces north, a wall
		local CORNER = { "#######", "#P....#", "#####.#", "#####.#", "#######" }
		local trace = sim.run(model(CORNER, "E", CFG), {
			seed = 1,
			ticks = 20,
			script = {
				sim.intent(10, "Right"),
				sim.expect(16, { x = 5, y = 1, heading = "S", moving = true }),
				sim.intent(16, "Back"),
				sim.expect(17, { x = 5, y = 1, heading = "N", moving = false }),
				sim.expect(20, { x = 5, y = 1, heading = "N", moving = false }),
			},
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(17)
	end)

	it("clears a buffered turn when reversing at a tile centre", function()
		-- Right (north, once reversed to west) is buffered at tick 9; Back at the (4,2) centre at tick 12.
		-- A kept buffer would turn north at the (3,2) junction at time 16.
		sim.run(model(BRANCHES, "E", CFG), {
			seed = 1,
			ticks = 20,
			script = {
				sim.intent(9, "Right"),
				sim.expect(12, { x = 4, y = 2, heading = "E" }),
				sim.intent(12, "Back"),
				sim.expect(17, { x = 2.75, y = 2, heading = "W" }),
			},
		})
	end)

	it("clears a buffered turn", function()
		-- Right is buffered, then Back twice: the player bounces off the west wall at tick 2 and
		-- heads east again. Without the buffer it passes the south branch at (5,2) and stops at (7,2).
		local trace = sim.run(model(BRANCHES, "E", CFG), {
			seed = 1,
			ticks = 30,
			script = {
				sim.intent(0, "Right"),
				sim.intent(1, "Back"),
				sim.expect(2, { x = 1, y = 2, moving = false }),
				sim.intent(2, "Back"),
				sim.expect(3, { x = 1.25, y = 2, heading = "E" }),
				sim.expect(19, { x = 5.25, y = 2, heading = "E" }),
				sim.expect(26, { x = 7, y = 2, moving = false }),
			},
		})
		local stops = {}
		for _, e in sim.events(trace, "Stopped") do
			table.insert(stops, e.tick)
		end
		t.expect(stops).toEqual({ 2, 26 })
	end)
end)
