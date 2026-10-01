--!strict
-- f0150 AC3: eating stops the player for a moment, as in the arcade: one frame of 1/60 s for a pellet
-- and three for a power pellet, which at 30 ticks a second and 30 units a tick is 15 and 45 units.
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- five pellets west of the spawn, and one in a pocket below it that these walks never reach, so the
-- level never clears
local CORRIDOR = Maze.parse({ "########", "#.....P#", "######.#", "########" }, "corridor")
-- four pellets, the last of them a power pellet, then the wall; one more lies behind the spawn
local WITH_POWER = Maze.parse({ "########", "#o...P.#", "########" }, "with-power")

local function config(slowdown: boolean): Session.Config
	return { movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4, eatSlowdown = slowdown }
end

local function modelWith(maze: Maze.Maze, cfg: Session.Config): sim.Model<Session.Session>
	return {
		name = "slowdown",
		tickRate = Session.TICK_RATE,
		new = function(seed: number): Session.Session
			local s = Session.new(maze, seed, cfg)
			Session.join(s, "p")
			return s
		end,
		step = function(s: Session.Session, intents: { any }, _k: number): { sim.Event }?
			local out: { any } = {}
			for _, i in intents do
				if i == "Kill" then
					for _, e in Session.kill(s, "p") do
						table.insert(out, e)
					end
				else
					Session.submit(s, "p", i)
				end
			end
			for _, e in Session.step(s) do
				table.insert(out, e)
			end
			return out :: any
		end,
		observe = function(s: Session.Session): any
			return Session.frame(s, "p")
		end,
	}
end

local function model(maze: Maze.Maze, slowdown: boolean): sim.Model<Session.Session>
	return modelWith(maze, config(slowdown))
end

local function eatTicks(trace: sim.Trace): { number }
	local out = {}
	for _, e in sim.events(trace, "PelletEaten") do
		table.insert(out, e.tick)
	end
	return out
end

-- x after walking `units` sub-tile units west of the spawn at x = 6 (120 units to a tile)
local function x(units: number): number
	return 6 - units / 120
end

return t.spec("f0150 eating slowdown", function(it)
	it("without the slowdown the player walks at a steady 30 units a tick", function()
		local trace = sim.run(model(CORRIDOR, false), { seed = 1, ticks = 24 })
		t.expect(eatTicks(trace)).toEqual({ 2, 6, 10, 14, 18 })
		for k = 0, 20 do
			t.expect(sim.state(trace, k).player.x).toBe(x(30 * k))
		end
	end)

	it("the pause for a pellet is 15 units: the tick after eating covers half a step", function()
		local trace = sim.run(model(CORRIDOR, true), { seed = 1, ticks = 30 })
		-- the first pellet is eaten at tick 2 (60 units), so tick 3 covers 15 units instead of 30
		t.expect(sim.state(trace, 2).player.x).toBe(x(60))
		t.expect(sim.state(trace, 3).player.x).toBe(x(75))
		t.expect(sim.state(trace, 4).player.x).toBe(x(105))
		t.expect(sim.state(trace, 5).player.x).toBe(x(135))
		t.expect(sim.state(trace, 6).player.x).toBe(x(165))
		t.expect(sim.state(trace, 7).player.x).toBe(x(195)) -- enters the second pellet's tile
		t.expect(sim.state(trace, 8).player.x).toBe(x(210)) -- and pauses again
	end)

	it("each pellet costs the same, so eating along a corridor comes a little later each time", function()
		local trace = sim.run(model(CORRIDOR, true), { seed = 1, ticks = 30 })
		t.expect(eatTicks(trace)).toEqual({ 2, 7, 11, 16, 20 })
		-- the player reaches the wall (600 units) at tick 23 instead of 20: five pauses of 15 units
		t.expect(sim.state(trace, 20).player.x).toBe(x(540))
		t.expect(sim.state(trace, 21).player.x).toBe(x(555)) -- the last pellet's pause
		t.expect(sim.state(trace, 22).player.x).toBe(x(585))
		t.expect(sim.state(trace, 23).player.x).toBe(x(600))
		t.expect(sim.firstTick(trace, "Stopped")).toBe(23)
	end)

	it("a power pellet stops the player for 45 units: one whole tick and half of the next", function()
		local trace = sim.run(model(WITH_POWER, true), { seed = 1, ticks = 40 })
		-- west of the spawn (x = 5): pellets at x = 4, 3, 2 and the power pellet at x = 1
		t.expect(eatTicks(trace)).toEqual({ 2, 7, 11, 16 })
		local items = {}
		for _, e in sim.events(trace, "PelletEaten") do
			table.insert(items, e.event.item)
		end
		t.expect(items).toEqual({ "pellet", "pellet", "pellet", "power" })
		local function at(k: number): number
			return 5 - sim.state(trace, k).player.x -- tiles walked west of the spawn
		end
		t.expect(at(16) * 120).toBe(435)
		t.expect(at(17) * 120).toBe(435) -- a whole tick without moving
		-- the rest is the walk on to the wall, four tiles on: how fast it goes depends on what comes after
		t.expect(at(19) * 120).toBe(480)
		t.expect(sim.firstTick(trace, "Stopped")).toBe(19)
	end)

	it("the pause only slows the player: score and pellets are the same", function()
		local slow = sim.run(model(CORRIDOR, true), { seed = 1, ticks = 40 })
		local fast = sim.run(model(CORRIDOR, false), { seed = 1, ticks = 40 })
		t.expect(sim.state(slow, 40).play.score).toBe(50)
		t.expect(sim.state(fast, 40).play.score).toBe(50)
		t.expect(#eatTicks(slow)).toBe(#eatTicks(fast))
	end)

	it("no pause is owed before anything is eaten, and none is carried past the end", function()
		-- an empty corridor: the same steady walk with the slowdown on
		local empty = Maze.parse({ "########", "#     P#", "######.#", "########" }, "empty")
		local trace = sim.run(model(empty, true), { seed = 1, ticks = 24 })
		for k = 0, 20 do
			t.expect(sim.state(trace, k).player.x).toBe(x(30 * k))
		end
	end)

	it("a pause still owed when the player dies is forgotten: the next attempt starts at full speed", function()
		local rules: Session.Config = {
			movement = { speed = 30, turnBufferTicks = 24 },
			maxIntentsPerTick = 4,
			eatSlowdown = true,
			play = {
				lives = 3,
				extraLifeScore = 0,
				readyTicks = 2,
				dyingTicks = 2,
				levelClearTicks = 3,
				tickRate = 30,
			},
		}
		-- the first pellet is eaten at tick 4, which owes 15 units; the player is caught at tick 4
		local trace = sim.run(modelWith(CORRIDOR, rules), { seed = 1, ticks = 14, script = { sim.intent(4, "Kill") } })
		t.expect(sim.events(trace, "PelletEaten")[1].tick).toBe(4)
		t.expect(#sim.events(trace, "LifeLost")).toBe(1)
		-- back at the spawn, in play again from tick 8: the first step covers the full 30 units
		t.expect(sim.state(trace, 8).player.x).toBe(6)
		t.expect(sim.state(trace, 8).play.phase).toBe("playing")
		t.expect(sim.state(trace, 9).player.x).toBe(x(30))
		t.expect(sim.state(trace, 10).player.x).toBe(x(60))
	end)

	it("a new level starts with nothing owed: the first step covers the full level speed", function()
		local small = Maze.parse({ "#####", "#..P#", "#####" }, "small")
		local rules: Session.Config = {
			movement = { speed = 30, turnBufferTicks = 24 },
			maxIntentsPerTick = 4,
			eatSlowdown = true,
			play = {
				lives = 3,
				extraLifeScore = 0,
				readyTicks = 2,
				dyingTicks = 2,
				levelClearTicks = 3,
				tickRate = 30,
			},
		}
		-- the last pellet of level 1 is eaten owing a pause; the level clears, and level 2 must start clean
		local trace = sim.run(modelWith(small, rules), { seed = 1, ticks = 24 })
		local playing = 0
		for _, e in sim.events(trace, "Playing") do
			if e.event.level == 2 then
				playing = e.tick
			end
		end
		t.expect(playing > 0).toBe(true)
		t.expect(sim.state(trace, playing).player.x).toBe(3)
		t.expect(sim.state(trace, playing + 1).player.x).toBeNear(3 - 34 / 120, 1e-9)
	end)

	it("a new run starts with nothing owed, even when the last life was lost owing a pause", function()
		local rules: Session.Config = {
			movement = { speed = 30, turnBufferTicks = 24 },
			maxIntentsPerTick = 4,
			eatSlowdown = true,
			play = {
				lives = 3,
				extraLifeScore = 0,
				readyTicks = 2,
				dyingTicks = 2,
				levelClearTicks = 3,
				tickRate = 30,
			},
		}
		local s = Session.new(CORRIDOR, 1, rules)
		Session.join(s, "p")
		for _ = 1, 3 do
			-- walk until a pellet is eaten, and die at once, so the pause for it is still owed
			local ate = false
			for _ = 1, 40 do
				for _, e in Session.step(s) do
					ate = ate or e.kind == "PelletEaten"
				end
				if ate then
					break
				end
			end
			t.expect(ate).toBe(true)
			t.expect(#Session.kill(s, "p")).toBe(1)
			for _ = 1, 2 do
				Session.step(s) -- the death pause, then (while lives remain) the countdown
			end
			while Session.frame(s, "p").play.phase == "ready" do
				Session.step(s)
			end
		end
		t.expect(Session.frame(s, "p").play.phase).toBe("gameover")
		t.expect((select(2, Session.playAgain(s, "p")))).toBe(true)
		while Session.frame(s, "p").play.phase ~= "playing" do
			Session.step(s)
		end
		t.expect(Session.frame(s, "p").player.x).toBe(6)
		Session.step(s)
		t.expect(Session.frame(s, "p").player.x).toBeNear(6 - 30 / 120, 1e-9)
	end)

	it("the slowdown is on in GAME_CONFIG and off in the default config", function()
		t.expect(Session.GAME_CONFIG.eatSlowdown).toBe(true)
		t.expect(Session.DEFAULT_CONFIG.eatSlowdown).toBe(nil)
	end)
end)
