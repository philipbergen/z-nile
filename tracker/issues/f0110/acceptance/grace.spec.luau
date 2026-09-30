--!strict
-- f0110 AC9: late turns (user, 2026-09-29). Cornering grace: a Left/Right arriving in the step right
-- after the player moved straight off a tile centre where that exit exists is taken there, cutting
-- the corner and keeping the distance already travelled past the centre. Missed turns: a later press
-- for an exit passed straight by is discarded while the player is nearer that junction than the next
-- one ahead with that exit, however many centres ago it was, so it never diverts the player later.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- East-west corridor on row 2 from the spawn (1,2) to (7,2), a north branch at (3,2), a south
-- branch at (5,2). Heading east at speed 30, the player is on (3,2) at time 8 and (5,2) at time 16.
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

local function run(script: { sim.Item }, ticks: number?)
	return sim.run(model(BRANCHES, "E", CFG), { seed = 1, ticks = ticks or 30, script = script })
end

return t.spec("f0110 cornering grace", function(it)
	it("a Left one tick after the junction centre cuts the corner there", function()
		local trace = run({
			sim.expect(9, { x = 3.25, y = 2, heading = "E" }),
			sim.intent(9, "Left"),
			sim.expect(10, { x = 3, y = 1.5, heading = "N", moving = true }),
		}, 12)
		t.expect(sim.firstTick(trace, function(e)
			return e.kind == "Entered" and e.x == 3 and e.y == 1
		end)).toBe(10)
	end)

	it("a Right one tick after the junction centre cuts the corner there", function()
		run({
			sim.intent(17, "Right"),
			sim.expect(18, { x = 5, y = 2.5, heading = "S", moving = true }),
		}, 20)
	end)

	it("two ticks late is not a grace turn", function()
		local trace = run({
			sim.intent(10, "Left"),
			sim.expect(11, { x = 3.75, y = 2, heading = "E" }),
			sim.expect(24, { x = 7, y = 2, heading = "E", moving = false }),
		})
		t.expect(sim.firstTick(trace, "Stopped")).toBe(24)
	end)

	it("a missed turn is discarded, not saved for a later junction with that exit", function()
		-- north exits at (3,2) and (5,2): Left two ticks after (3,2) is nearer (3,2) than (5,2)
		local TWO = { "#########", "###.#.###", "#P......#", "#########" }
		sim.run(model(TWO, "E", CFG), {
			seed = 1,
			ticks = 18,
			script = {
				sim.intent(10, "Left"),
				sim.expect(16, { x = 5, y = 2, heading = "E" }),
				sim.expect(17, { x = 5.25, y = 2, heading = "E" }),
			},
		})
	end)

	it("a press nearer the next junction with that exit is buffered for it", function()
		-- at time 13 the player is past (4,2), which has no north exit: Left is for (5,2)
		local TWO = { "#########", "###.#.###", "#P......#", "#########" }
		sim.run(model(TWO, "E", CFG), {
			seed = 1,
			ticks = 18,
			script = {
				sim.intent(11, "Left"), -- 0.75 past (3,2), 1.25 before (5,2): still missed
				sim.expect(16, { x = 5, y = 2, heading = "E" }),
			},
		})
		sim.run(model(TWO, "E", CFG), {
			seed = 1,
			ticks = 18,
			script = {
				sim.intent(13, "Left"),
				sim.expect(16, { x = 5, y = 2, heading = "N" }),
				sim.expect(17, { x = 5, y = 1.75, heading = "N" }),
			},
		})
	end)

	it("with adjacent junctions, a press no nearer the passed one is kept for the next", function()
		-- north exits at (3,2) and (4,2): Left two ticks after (3,2) is half a tile from each, so it is
		-- buffered (a tie goes to the junction ahead) and taken at (4,2)
		local PAIR = { "#########", "###..####", "#P......#", "#########" }
		sim.run(model(PAIR, "E", CFG), {
			seed = 1,
			ticks = 14,
			script = {
				sim.intent(10, "Left"),
				sim.expect(12, { x = 4, y = 2, heading = "N" }),
				sim.expect(13, { x = 4, y = 1.75, heading = "N" }),
			},
		})
	end)

	it("after turning at a centre, a press for a turn that centre had is buffered, not missed", function()
		-- Right turns south at (5,1); Left (east) there is not a missed turn, since the player did not
		-- go straight through: it is taken at (5,3), the next east exit
		local HOOK = { "#########", "#P......#", "#####.###", "#####..##", "#####.###", "#########" }
		sim.run(model(HOOK, "E", CFG), {
			seed = 1,
			ticks = 26,
			script = {
				sim.intent(13, "Right"),
				sim.expect(16, { x = 5, y = 1, heading = "S" }),
				sim.intent(18, "Left"),
				sim.expect(24, { x = 5, y = 3, heading = "E" }),
				sim.expect(25, { x = 5.25, y = 3, heading = "E" }),
			},
		})
	end)

	it("grace applies only after going straight through the centre, not after turning there", function()
		-- Right at 13 turns south at (5,2); a second Right at 17 is not a grace U-turn back west
		run({
			sim.intent(13, "Right"),
			sim.intent(17, "Right"),
			sim.expect(18, { x = 5, y = 2.5, heading = "S" }),
		}, 20)
	end)

	it("the grace is one tick at any speed, not up to the half tile", function()
		-- at speed 20 the player is on (3,2) at time 12; two ticks later it is only 1/3 tile past
		local slow = { speed = 20, turnBufferTicks = 24 }
		sim.run(model(BRANCHES, "E", slow), {
			seed = 1,
			ticks = 16,
			script = {
				sim.intent(13, "Left"),
				sim.expect(14, function(obs: any)
					t.expect(obs.heading).toBe("N")
					t.expect(obs.x).toBe(3)
					t.expect(obs.y).toBeNear(2 - 40 / 120, 1e-12) -- 20 units past the centre, plus 20
				end),
			},
		})
		sim.run(model(BRANCHES, "E", slow), {
			seed = 1,
			ticks = 16,
			script = { sim.intent(14, "Left"), sim.expect(15, { x = 3.5, y = 2, heading = "E" }) },
		})
	end)

	it("without that exit at the centre just passed, the press is buffered as usual", function()
		-- Right (south) one tick after (3,2), which has no south exit: taken at (5,2) instead
		run({
			sim.intent(9, "Right"),
			sim.expect(10, { x = 3.5, y = 2, heading = "E" }),
			sim.expect(16, { x = 5, y = 2, heading = "S" }),
			sim.expect(17, { x = 5, y = 2.25, heading = "S" }),
		})
	end)

	it("a grace turn uses up the press: it does not also fire at a later corner", function()
		-- north branch from (3,3) up to a corner at (3,1) that turns west; a leftover Left would turn there
		local HOOK = { "#######", "#...###", "###.###", "#P....#", "#######" }
		sim.run(model(HOOK, "E", CFG), {
			seed = 1,
			ticks = 20,
			script = {
				sim.intent(9, "Left"),
				sim.expect(10, { x = 3, y = 2.5, heading = "N" }),
				sim.expect(16, { x = 3, y = 1, heading = "N", moving = false }),
				sim.expect(17, { x = 3, y = 1, heading = "N", moving = false }),
			},
		})
	end)
	it("a late press stays missed after the player passes further centres without that exit", function()
		-- north exits at (3,2) and (6,2) (design-review-004 F1): Left at 13 is 1.25 tiles past (3,2)
		-- and 1.75 before (6,2), so it is discarded even though (4,2) was passed since
		local LONG = { "##########", "###.##.###", "#P.......#", "##########" }
		sim.run(model(LONG, "E", CFG), {
			seed = 1,
			ticks = 22,
			script = {
				sim.intent(13, "Left"),
				sim.expect(21, { x = 6.25, y = 2, heading = "E" }),
			},
		})
		-- Left at 12 arrives on the (4,2) centre, which has no north exit: still missed
		sim.run(model(LONG, "E", CFG), {
			seed = 1,
			ticks = 22,
			script = {
				sim.intent(12, "Left"),
				sim.expect(21, { x = 6.25, y = 2, heading = "E" }),
			},
		})
		-- Left at 15 is 2.25 tiles past (3,2) and 0.75 before (6,2): buffered and taken there
		sim.run(model(LONG, "E", CFG), {
			seed = 1,
			ticks = 22,
			script = {
				sim.intent(15, "Left"),
				sim.expect(20, { x = 6, y = 2, heading = "N" }),
				sim.expect(21, { x = 6, y = 1.75, heading = "N" }),
			},
		})
	end)

	it("a turn right after Back at a centre is buffered, not a grace turn", function()
		-- Back on the (3,2) centre, then Right (north, which (3,2) has): no spin off sideways
		run({
			sim.intent(8, "Back"),
			sim.intent(9, "Right"),
			sim.expect(10, { x = 2.5, y = 2, heading = "W" }),
		}, 12)
	end)

	it("after Back mid-tile, a press is not missed for a junction never passed that way", function()
		-- south exits at (2,1) and (5,1): Back at 14 (between (4,1) and (5,1)), then Left (south) is
		-- buffered and taken at (2,1), not discarded as a miss of (5,1)
		local SOUTH = { "#########", "#P......#", "##.##.###", "#########" }
		sim.run(model(SOUTH, "E", CFG), {
			seed = 1,
			ticks = 26,
			script = {
				sim.intent(14, "Back"),
				sim.intent(15, "Left"),
				sim.expect(25, { x = 2, y = 1.25, heading = "S" }),
			},
		})
	end)

	it("a missed press also clears an older buffered turn", function()
		-- Right at 5 is buffered ((2,2) has no south exit); Left at 10 is a miss of (3,2) and replaces
		-- it, so the player does not turn south at (5,2)
		run({
			sim.intent(5, "Right"),
			sim.intent(10, "Left"),
			sim.expect(17, { x = 5.25, y = 2, heading = "E" }),
		}, 18)
	end)

	it("a grace turn also clears an older buffered turn", function()
		-- Right at 5 is buffered; Left at 9 is a grace turn north at (3,3). The old Right would turn
		-- east at the (3,1) corner; without it the player stops there
		local CORNER = { "#######", "###...#", "###.###", "#P....#", "#######" }
		sim.run(model(CORNER, "E", CFG), {
			seed = 1,
			ticks = 18,
			script = {
				sim.intent(5, "Right"),
				sim.intent(9, "Left"),
				sim.expect(17, { x = 3, y = 1, heading = "N", moving = false }),
			},
		})
	end)

	it("leaving the spawn is not going straight through it: no grace or miss there", function()
		-- the spawn (1,2) has a north exit; Left one tick after leaving it is buffered for (3,2)
		local SPAWN = { "#######", "#.#.###", "#P....#", "#######" }
		sim.run(model(SPAWN, "E", CFG), {
			seed = 1,
			ticks = 10,
			script = {
				sim.intent(1, "Left"),
				sim.expect(2, { x = 1.5, y = 2, heading = "E" }),
				sim.expect(8, { x = 3, y = 2, heading = "N" }),
			},
		})
	end)
end)
