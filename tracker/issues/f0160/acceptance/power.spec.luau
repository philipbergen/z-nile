--!strict
-- f0160 AC1: eating a power pellet starts the level's frightened period (the ghosts' reaction is raft
-- d's): a PowerStarted event with its length in ticks, a timer that runs down while the run is in
-- play, and a restart, not an extension, when another power pellet is eaten meanwhile.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- the spawn is at x = 5; pellets at x = 4 and 3 and 2, then a power pellet at x = 1. A pellet in a pocket
-- below the spawn is never reached, so the level never clears.
local ONE_POWER = Maze.parse({ "#######", "#o...P#", "#####.#", "#######" }, "one-power")
-- a power pellet at x = 3 and another at x = 1
local TWO_POWER = Maze.parse({ "#######", "#o.o.P#", "#####.#", "#######" }, "two-power")

-- a corridor 57 tiles long, spawn at its east end: the power pellet is the first tile, then two dots and
-- a long empty run, so a whole frightened period (180 ticks at up to 34 units) fits before the wall. A
-- pocket pellet below the spawn is never reached, so the level never clears.
local LONG = Maze.parse({
	string.rep("#", 60),
	"#" .. string.rep(" ", 54) .. "..o" .. "P#",
	string.rep("#", 58) .. ".#",
	string.rep("#", 60),
}, "long")

local PLAIN: Session.Config = { movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4 }

local function model(maze: Maze.Maze, config: Session.Config): sim.Model<Session.Session>
	return {
		name = "power",
		tickRate = Session.TICK_RATE,
		new = function(seed: number): Session.Session
			local s = Session.new(maze, seed, config)
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

-- a run at level `level` that has just started playing, made only through Game's public API
local function atLevel(level: number): Game.Game
	local g = Game.new(Game.IMMEDIATE_CONFIG)
	for _ = 1, level - 1 do
		Game.cleared(g)
		Game.step(g) -- the level-clear pause is over: next level, in play
	end
	t.expect(g.level).toBe(level)
	t.expect(g.phase).toBe("playing")
	return g
end

return t.spec("f0160 power pellets", function(it)
	it("eating a power pellet reports PowerStarted with the level's frightened time in ticks", function()
		local trace = sim.run(model(ONE_POWER, PLAIN), { seed = 1, ticks = 20 })
		local started = sim.events(trace, "PowerStarted")
		t.expect(#started).toBe(1)
		t.expect(started[1].tick).toBe(14) -- the tick it is eaten: x = 1 is entered at tick 14
		t.expect(started[1].event.ticks).toBe(180) -- level 1: 6 seconds at 30 ticks a second
		t.expect(started[1].event.level).toBe(1)
		t.expect(started[1].event.player).toBe("p")
		t.expect(sim.events(trace, "PelletEaten")[4].event.item).toBe("power")
	end)

	it("the frightened time shows in the frame and runs down one tick at a time", function()
		local trace = sim.run(model(ONE_POWER, PLAIN), { seed = 1, ticks = 30 })
		t.expect(sim.state(trace, 13).play.frightened).toBe(0)
		t.expect(sim.state(trace, 14).play.frightened).toBe(180)
		t.expect(sim.state(trace, 15).play.frightened).toBe(179)
		t.expect(sim.state(trace, 24).play.frightened).toBe(170)
	end)

	it("it ends after exactly that many ticks, with a PowerEnded event", function()
		local trace = sim.run(model(ONE_POWER, PLAIN), { seed = 1, ticks = 200 })
		t.expect(sim.state(trace, 193).play.frightened).toBe(1)
		t.expect(sim.state(trace, 194).play.frightened).toBe(0)
		local ended = sim.events(trace, "PowerEnded")
		t.expect(#ended).toBe(1)
		t.expect(ended[1].tick).toBe(194)
		t.expect(ended[1].event.level).toBe(1)
		t.expect(sim.state(trace, 200).play.frightened).toBe(0)
	end)

	it("a second power pellet restarts the period: it does not add to what is left", function()
		local trace = sim.run(model(TWO_POWER, PLAIN), { seed = 1, ticks = 40 })
		-- the first is eaten at tick 6 (x = 3), the second at tick 14 (x = 1)
		local started = sim.events(trace, "PowerStarted")
		t.expect(#started).toBe(2)
		t.expect(started[1].tick).toBe(6)
		t.expect(started[2].tick).toBe(14)
		t.expect(sim.state(trace, 13).play.frightened).toBe(180 - 7)
		t.expect(sim.state(trace, 14).play.frightened).toBe(180) -- back to a full period, not 353
		t.expect(sim.state(trace, 15).play.frightened).toBe(179)
	end)

	it("the player runs at the frightened speed while the period lasts: 34 units a tick, not 30", function()
		local trace = sim.run(model(LONG, PLAIN), { seed = 1, ticks = 190 })
		-- units walked west of the spawn (the spawn is at x = 58)
		local function units(k: number): number
			return math.floor((58 - sim.state(trace, k).player.x) * 120 + 0.5)
		end
		t.expect(sim.events(trace, "PowerStarted")[1].tick).toBe(2)
		t.expect(units(2) - units(1)).toBe(30) -- the step that eats it is still a normal one
		t.expect(units(3) - units(2)).toBe(34) -- the next one is fast
		t.expect(units(181) - units(180)).toBe(34)
		t.expect(units(182) - units(181)).toBe(34) -- the last step of the period: it ends with this tick
		t.expect(sim.events(trace, "PowerEnded")[1].tick).toBe(182)
		t.expect(units(183) - units(182)).toBe(30) -- normal again
		t.expect(units(184) - units(183)).toBe(30)
	end)

	it("a dot eaten while frightened costs 17 units, the pause at the frightened speed", function()
		local slow: Session.Config =
			{ movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4, eatSlowdown = true }
		local trace = sim.run(model(LONG, slow), { seed = 1, ticks = 14 })
		local function units(k: number): number
			return math.floor((58 - sim.state(trace, k).player.x) * 120 + 0.5)
		end
		-- the energizer is eaten at tick 2 at the normal speed and owes 45 units; the dot at tick 7 is eaten
		-- at 34 and owes 17
		local eaten = {}
		for _, e in sim.events(trace, "PelletEaten") do
			table.insert(eaten, e.tick)
		end
		t.expect(eaten).toEqual({ 2, 7, 11 })
		t.expect(units(3)).toBe(60) -- a whole step owed
		t.expect(units(4)).toBe(83)
		t.expect(units(7)).toBe(185)
		t.expect(units(8)).toBe(202) -- 34 - 17
		t.expect(units(12)).toBe(321)
	end)

	it("a power pellet is worth 50 points, like the arcade's", function()
		local trace = sim.run(model(ONE_POWER, PLAIN), { seed = 1, ticks = 20 })
		t.expect(sim.state(trace, 13).play.score).toBe(30)
		t.expect(sim.state(trace, 14).play.score).toBe(80)
	end)

	it("the period is the level's: 150 ticks on level 2, 30 on level 9, none from level 17", function()
		for level, want in
			-- level 18 has a second of it again: only levels 17, 19, 20 and from 21 on have none
			{
				[1] = 180,
				[2] = 150,
				[3] = 120,
				[4] = 90,
				[5] = 60,
				[9] = 30,
				[14] = 90,
				[17] = 0,
				[18] = 30,
				[19] = 0,
				[20] = 0,
				[30] = 0,
			}
		do
			local g = atLevel(level)
			local events = Game.power(g)
			t.expect(#events).toBe(1)
			t.expect(events[1].kind).toBe("PowerStarted")
			t.expect(events[1].ticks).toBe(want)
			t.expect(events[1].level).toBe(level)
			t.expect(g.frightened).toBe(want)
		end
	end)

	it("level 18's single second runs out after exactly 30 ticks", function()
		local g = atLevel(18)
		t.expect(Game.power(g)[1].ticks).toBe(30)
		for _ = 1, 29 do
			t.expect(#Game.step(g)).toBe(0)
		end
		local last = Game.step(g)
		t.expect(#last).toBe(1)
		t.expect(last[1].kind).toBe("PowerEnded")
	end)

	it(
		"with no frightened time (levels 17, 19, 20, 21 on) a zero-length PowerStarted is reported and no PowerEnded follows",
		function()
			local g = atLevel(17)
			Game.power(g)
			t.expect(g.frightened).toBe(0)
			for _ = 1, 5 do
				t.expect(#Game.step(g)).toBe(0) -- no PowerEnded for a period that never began
			end
		end
	)

	it("the period only runs down while the run is in play", function()
		local g = Game.new({
			lives = 3,
			extraLifeScore = 0,
			readyTicks = 2,
			dyingTicks = 2,
			levelClearTicks = 2,
			tickRate = 30,
		})
		Game.step(g)
		Game.step(g) -- playing
		Game.power(g)
		Game.step(g)
		t.expect(g.frightened).toBe(179)
		-- a death cancels it, and while dying or ready nothing counts down
		Game.died(g)
		t.expect(g.frightened).toBe(0)
		Game.step(g)
		Game.step(g) -- respawn: ready
		t.expect(g.frightened).toBe(0)
	end)

	it("a death or a cleared level ends the period without a PowerEnded event", function()
		local trace = sim.run(model(ONE_POWER, PLAIN), {
			seed = 1,
			ticks = 40,
			script = { sim.intent(20, "Kill") },
		})
		t.expect(sim.state(trace, 20).play.frightened).toBe(180 - 6)
		t.expect(sim.state(trace, 21).play.frightened).toBe(0)
		t.expect(#sim.events(trace, "PowerEnded")).toBe(0)
		-- and clearing the level does the same
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.power(g)
		t.expect(g.frightened).toBe(180)
		Game.cleared(g)
		t.expect(g.frightened).toBe(0)
	end)

	it("the frightened period is deterministic per seed", function()
		for _, seed in sim.seeds(3) do
			sim.assertDeterministic(model(TWO_POWER, PLAIN), { seed = seed, ticks = 220 })
		end
	end)
end)
