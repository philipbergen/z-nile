--!strict
-- f0150 AC4: eating the last pellet clears the level. The next level puts every pellet back, sends the
-- player home and runs at that level's speed; the score and lives carry over, and a new run resets all.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local sim = require("@tests/lib/sim")
local t = require("@tests/lib/t")

-- the spawn is at x = 3: pellets at x = 2 and x = 1, then the wall
local SMALL = Maze.parse({ "#####", "#..P#", "#####" }, "small")

local function model(config: Session.Config): sim.Model<Session.Session>
	return {
		name = "level",
		tickRate = Session.TICK_RATE,
		new = function(seed: number): Session.Session
			local s = Session.new(SMALL, seed, config)
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
				elseif i == "Again" then
					for _, e in (Session.playAgain(s, "p")) do
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

-- a short pause at each change, so the phases are easy to see: ready 2, dying 2, level clear 3
local PAUSES: Game.Config =
	{ lives = 3, extraLifeScore = 10000, readyTicks = 2, dyingTicks = 2, levelClearTicks = 3, tickRate = 30 }
local RULES: Session.Config =
	{ movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4, play = PAUSES }
local PLAIN: Session.Config = { movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4 }

local function eatTicks(trace: sim.Trace): { number }
	local out = {}
	for _, e in sim.events(trace, "PelletEaten") do
		table.insert(out, e.tick)
	end
	return out
end

return t.spec("f0150 clearing a level", function(it)
	it("eating the last pellet reports LevelCleared and starts the level-clear pause", function()
		local trace = sim.run(model(RULES), { seed = 1, ticks = 12 })
		-- ready for 2 ticks, then the player walks: pellets at ticks 4 and 8 of the run
		local cleared = sim.events(trace, "LevelCleared")
		t.expect(#cleared).toBe(1)
		t.expect(cleared[1].event.level).toBe(1)
		t.expect(cleared[1].event.score).toBe(20)
		local atClear = sim.state(trace, cleared[1].tick)
		t.expect(atClear.play.phase).toBe("levelclear")
		t.expect(atClear.play.score).toBe(20)
		t.expect(atClear.play.timer).toBe(3)
	end)

	it("the player stands still during the pause, and the next level starts at the spawn", function()
		local trace = sim.run(model(RULES), { seed = 1, ticks = 14 })
		local cleared = sim.events(trace, "LevelCleared")[1].tick
		local xAtClear = sim.state(trace, cleared).player.x
		for k = cleared, cleared + 2 do
			t.expect(sim.state(trace, k).player.x).toBe(xAtClear)
		end
		local ready = sim.events(trace, "Ready")[1]
		t.expect(ready.event.reason).toBe("level")
		t.expect(ready.event.level).toBe(2)
		t.expect(ready.tick).toBe(cleared + 3) -- the pause is 3 ticks
		local at = sim.state(trace, ready.tick)
		t.expect(at.player.x).toBe(3) -- home
		t.expect(at.player.heading).toBe("W")
		t.expect(at.play.level).toBe(2)
		t.expect(at.play.phase).toBe("ready")
		t.expect(at.player.jumpTick).toBe(ready.tick) -- a teleport
		t.expect(at.play.score).toBe(20) -- the score carries over
		t.expect(at.play.lives).toBe(3)
	end)

	it("every pellet is back on the new level, and eating them scores again", function()
		local trace = sim.run(model(RULES), { seed = 1, ticks = 20 })
		local ticks = eatTicks(trace)
		t.expect(ticks).toEqual({ 4, 8, 15, 19 }) -- two on level 1, the same two on level 2, a bit faster
		t.expect(sim.state(trace, 20).play.score).toBe(40)
		local cleared = sim.events(trace, "LevelCleared")
		t.expect(#cleared).toBe(2)
		t.expect(cleared[2].event.level).toBe(2)
	end)

	it("the new level runs at the new level's speed: 34 units a tick on level 2", function()
		local trace = sim.run(model(RULES), { seed = 1, ticks = 16 })
		local second = sim.events(trace, "Ready")[1].tick + 2 -- level 2 play starts 2 ticks after its Ready
		local a = sim.state(trace, second + 1).player.x
		local b = sim.state(trace, second + 2).player.x
		t.expect(a - b).toBeNear(34 / 120, 1e-9)
		-- and level 1 ran at 30
		t.expect(sim.state(trace, 3).player.x - sim.state(trace, 4).player.x).toBeNear(30 / 120, 1e-9)
	end)

	it("eating on level 2 pauses for 17 units, not 15", function()
		local config: Session.Config = {
			movement = { speed = 30, turnBufferTicks = 24 },
			maxIntentsPerTick = 4,
			play = PAUSES,
			eatSlowdown = true,
		}
		local trace = sim.run(model(config), { seed = 1, ticks = 24 })
		local ready = sim.events(trace, "Ready")[1].tick
		-- level 2 play starts at ready + 2; the first pellet is eaten when 60 units are covered
		local first: number = 0
		for _, e in sim.events(trace, "PelletEaten") do
			if e.tick > ready then
				first = e.tick
				break
			end
		end
		t.expect(first > ready).toBe(true)
		local before = sim.state(trace, first).player.x
		local after = sim.state(trace, first + 1).player.x
		t.expect(before - after).toBeNear((34 - 17) / 120, 1e-9)
	end)

	it("the level-clear pause and the respawn reset the player; a death keeps the eaten pellets", function()
		-- eat one pellet, die, come back: the eaten pellet stays eaten, the other is still there
		local trace = sim.run(model(RULES), {
			seed = 1,
			ticks = 22,
			script = { sim.intent(6, "Kill") }, -- after the first pellet (tick 4), before the second (tick 8)
		})
		t.expect(#sim.events(trace, "LifeLost")).toBe(1)
		local eaten = eatTicks(trace)
		t.expect(#eaten).toBe(2) -- the pellet eaten before the death is not eaten again
		t.expect(sim.events(trace, "Ready")[1].event.reason).toBe("respawn")
		t.expect(#sim.events(trace, "LevelCleared")).toBe(1) -- and the level still clears on the last one
	end)

	it("a kill during the level-clear pause does nothing: the level still advances", function()
		-- the last pellet is eaten at tick 8, so tick 8 is inside the pause
		local trace = sim.run(model(RULES), { seed = 1, ticks = 14, script = { sim.intent(8, "Kill") } })
		t.expect(sim.state(trace, 8).play.phase).toBe("levelclear")
		t.expect(#sim.events(trace, "LifeLost")).toBe(0)
		local levelReady
		for _, e in sim.events(trace, "Ready") do
			levelReady = levelReady or e
		end
		t.expect(levelReady.event.reason).toBe("level")
		local f = sim.state(trace, levelReady.tick)
		t.expect(f.play.level).toBe(2)
		t.expect(f.play.lives).toBe(3)
	end)

	it("lives carry over to the next level: a life lost on level 1 is still lost on level 2", function()
		-- die once after the first pellet, then clear the level
		local trace = sim.run(model(RULES), { seed = 1, ticks = 30, script = { sim.intent(6, "Kill") } })
		local levelReady
		for _, e in sim.events(trace, "Ready") do
			if e.event.reason == "level" then
				levelReady = levelReady or e
			end
		end
		t.expect(levelReady ~= nil).toBe(true)
		local f = sim.state(trace, levelReady.tick)
		t.expect(f.play.level).toBe(2)
		t.expect(f.play.lives).toBe(2)
	end)

	it("play again after gameover puts every pellet back and starts over from level 1", function()
		local script: { sim.Item } = {}
		-- three deaths: each time, kill once the player is walking (ready 2 + dying 2 between them)
		for _, at in { 6, 12, 18 } do
			table.insert(script, sim.intent(at, "Kill"))
		end
		table.insert(script, sim.intent(30, "Kill")) -- nothing to kill: the run is over
		table.insert(script, sim.intent(40, "Again"))
		-- play again at 40; the new run clears level 1 at tick 48 and goes on to level 2 after it
		local trace = sim.run(model(RULES), { seed = 1, ticks = 50, script = script })
		t.expect(#sim.events(trace, "GameOver")).toBe(1)
		t.expect(#sim.events(trace, "LifeLost")).toBe(3) -- the kill after game over cost nothing
		t.expect(sim.state(trace, 35).play.lives).toBe(0)
		local again = {}
		for _, e in sim.events(trace, "Ready") do
			if e.event.reason == "again" then
				table.insert(again, e)
			end
		end
		t.expect(#again).toBe(1)
		-- the pellet eaten before the first death (tick 4) is eaten again in the new run
		local after = 0
		for _, e in sim.events(trace, "PelletEaten") do
			if e.tick > again[1].tick then
				after += 1
			end
		end
		t.expect(after).toBe(2)
		local f = sim.state(trace, again[1].tick)
		t.expect(f.play.level).toBe(1)
		t.expect(f.play.score).toBe(0)
		t.expect(f.play.lives).toBe(3)
		t.expect(f.play.phase).toBe("ready")
		-- the pellets are back: the new run eats them and clears the level again
		local cleared = sim.events(trace, "LevelCleared")
		t.expect(#cleared).toBe(1)
		t.expect(cleared[1].tick > again[1].tick).toBe(true)
	end)

	it("with no pauses a cleared level rolls straight on", function()
		local trace = sim.run(model(PLAIN), { seed = 1, ticks = 30 })
		t.expect(#sim.events(trace, "LevelCleared") >= 1).toBe(true)
		t.expect(sim.state(trace, 30).play.level >= 2).toBe(true)
	end)
end)
