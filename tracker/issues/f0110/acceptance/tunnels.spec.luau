--!strict
-- f0110 AC6: the door stops the player; tunnels wrap, and every jump in position is a Wrapped event.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

local DOOR = { "#######", "#P.-H##", "#######" }
local TUNNEL = { "#####", "  P  ", "#####" } -- width 5, wraps on row 1
local SHAFT = { "#.#", "#P#", "#.#" } -- height 3, wraps on column 1

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

-- Every tick where the position jumps by more than a tile has a Wrapped event, and vice versa.
local function wrapsMatchJumps(trace: sim.Trace)
	local wrapped: { [number]: boolean } = {}
	for _, e in sim.events(trace, "Wrapped") do
		t.expect(wrapped[e.tick]).toBe(nil) -- at most one per step
		wrapped[e.tick] = true
	end
	for tk = 1, trace.steps do
		local a, b = sim.state(trace, tk - 1), sim.state(trace, tk)
		local jump = math.abs(b.x - a.x) > 1 or math.abs(b.y - a.y) > 1
		if jump ~= (wrapped[tk] == true) then
			error(`tick {tk}: jump = {jump} but Wrapped = {wrapped[tk] == true} ({a.x},{a.y} -> {b.x},{b.y})`)
		end
	end
end

return t.spec("f0110 doors and tunnels", function(it)
	it("the ghost door stops the player like a wall", function()
		local trace = sim.run(model(DOOR, "E", CFG), {
			seed = 1,
			ticks = 20,
			script = {
				sim.expect(4, { x = 2, y = 1, moving = false }),
				sim.expect(20, { x = 2, y = 1, moving = false }),
			},
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(4)
	end)

	it("wraps through a horizontal tunnel and keeps going", function()
		local trace = sim.run(model(TUNNEL, "E", CFG), {
			seed = 1,
			ticks = 60,
			script = {
				sim.expect(8, { x = 4, y = 1 }),
				sim.expect(11, { x = 4.75, y = 1 }),
				sim.expect(12, { x = 0, y = 1, moving = true }),
				sim.expect(16, { x = 1, y = 1 }),
			},
		})
		local ticks = {}
		for _, e in sim.events(trace, "Wrapped") do
			table.insert(ticks, e.tick)
		end
		t.expect(ticks).toEqual({ 12, 32, 52 })
		t.expect(sim.firstTick(trace, function(e)
			return e.kind == "Entered" and e.x == 0
		end)).toBe(10)
		wrapsMatchJumps(trace)
	end)

	it("wraps through a vertical tunnel", function()
		local trace = sim.run(model(SHAFT, "N", CFG), {
			seed = 1,
			ticks = 30,
			script = { sim.expect(4, { x = 1, y = 0 }), sim.expect(8, { x = 1, y = 2 }) },
		})
		t.expect(#sim.events(trace, "Wrapped") > 0).toBe(true)
		wrapsMatchJumps(trace)
	end)

	it("Back on the tunnel seam keeps the player in place, modulo the maze width", function()
		local trace = sim.run(model(TUNNEL, "E", CFG), {
			seed = 1,
			ticks = 16,
			script = {
				sim.expect(10, { x = 4.5 }),
				sim.intent(10, "Back"),
				sim.expect(11, function(obs: any)
					t.expect(obs.heading).toBe("W")
					t.expect(obs.x % 5).toBe(4.25)
				end),
				sim.expect(12, function(obs: any)
					t.expect(obs.x % 5).toBe(4)
				end),
				sim.expect(16, function(obs: any)
					t.expect(obs.x % 5).toBe(3)
				end),
			},
		})
		wrapsMatchJumps(trace)
	end)
end)
