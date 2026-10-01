--!strict
-- f0170 AC2: Game, the rules of one run, as a pure state machine. It is stepped once per tick and told
-- what happened; it never looks at a maze.
local Game = require("@logic/Game")
local t = require("@tests/lib/t")

-- small numbers make the timings easy to read: ready 3 ticks, dying 2, level clear 4
local SMALL: Game.Config =
	{ lives = 3, extraLifeScore = 10000, readyTicks = 3, dyingTicks = 2, levelClearTicks = 4, tickRate = 30 }

local function kinds(events: { Game.Event }): { string }
	local out = {}
	for _, e in events do
		table.insert(out, e.kind)
	end
	return out
end

-- steps until the phase changes; returns how many steps it took and the events of the last one
local function stepsUntilChange(g: Game.Game): (number, { Game.Event })
	local from = g.phase
	for n = 1, 500 do
		local events = Game.step(g)
		if g.phase ~= from then
			return n, events
		end
	end
	error("the phase never changed")
end

return t.spec("f0170 Game", function(it)
	it(
		"the classic rules: 3 lives, an extra life at 10,000, pauses of 2, 1.5 and 2 seconds at 30 Hz",
		function()
			local c = Game.CLASSIC_CONFIG
			t.expect(c.lives).toBe(3)
			t.expect(c.extraLifeScore).toBe(10000)
			t.expect(c.readyTicks).toBe(60)
			t.expect(c.dyingTicks).toBe(45)
			t.expect(c.levelClearTicks).toBe(60)
			t.expect(c.tickRate).toBe(30)
			local i = Game.IMMEDIATE_CONFIG
			t.expect(i.readyTicks + i.dyingTicks + i.levelClearTicks).toBe(0)
			t.expect(i.lives).toBe(3)
		end
	)

	it("a new run starts in ready, with level 1, score 0, full lives and the ready countdown", function()
		local g = Game.new(SMALL)
		t.expect(g.phase).toBe("ready")
		t.expect(g.level).toBe(1)
		t.expect(g.score).toBe(0)
		t.expect(g.lives).toBe(3)
		t.expect(g.timer).toBe(3)
		t.expect(g.frightened).toBe(0)
		t.expect(Game.canMove(g)).toBe(false)
		t.expect(Game.new().timer).toBe(60) -- the classic rules by default
	end)

	it("with no ready pause, the run starts in play", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		t.expect(g.phase).toBe("playing")
		t.expect(Game.canMove(g)).toBe(true)
	end)

	it("ready lasts exactly readyTicks steps, then play starts with a Playing event", function()
		local g = Game.new(SMALL)
		local n, events = stepsUntilChange(g)
		t.expect(n).toBe(3)
		t.expect(g.phase).toBe("playing")
		t.expect(kinds(events)).toEqual({ "Playing" })
		t.expect(Game.canMove(g)).toBe(true)
		t.expect(g.timer).toBe(0)
	end)

	it("a death costs a life and pauses for dyingTicks, then a new attempt starts", function()
		local g = Game.new(SMALL)
		stepsUntilChange(g)
		local events = Game.died(g)
		t.expect(kinds(events)).toEqual({ "LifeLost" })
		t.expect(events[1].lives).toBe(2)
		t.expect(g.lives).toBe(2)
		t.expect(g.phase).toBe("dying")
		t.expect(Game.canMove(g)).toBe(false)
		local n, after = stepsUntilChange(g)
		t.expect(n).toBe(2)
		t.expect(kinds(after)).toEqual({ "Ready" })
		t.expect(after[1].reason).toBe("respawn")
		t.expect(g.phase).toBe("ready")
		t.expect(g.timer).toBe(3)
		t.expect(g.level).toBe(1)
	end)

	it("losing the last life ends the run with a GameOver carrying score and level", function()
		local g = Game.new(SMALL)
		Game.step(g)
		Game.step(g)
		Game.step(g)
		Game.addScore(g, 70)
		for _ = 1, 2 do
			Game.died(g)
			stepsUntilChange(g) -- dying -> ready
			stepsUntilChange(g) -- ready -> playing
		end
		t.expect(g.lives).toBe(1)
		Game.died(g)
		t.expect(g.lives).toBe(0)
		local _, events = stepsUntilChange(g)
		t.expect(g.phase).toBe("gameover")
		t.expect(kinds(events)).toEqual({ "GameOver" })
		t.expect(events[1].score).toBe(70)
		t.expect(events[1].level).toBe(1)
		t.expect(Game.canMove(g)).toBe(false)
		for _ = 1, 20 do
			t.expect(#Game.step(g)).toBe(0) -- nothing happens by itself after gameover
		end
		t.expect(g.phase).toBe("gameover")
	end)

	it("only a run in play can lose a life or clear a level", function()
		local g = Game.new(SMALL) -- ready
		t.expect(#Game.died(g)).toBe(0)
		t.expect(#Game.cleared(g)).toBe(0)
		t.expect(g.lives).toBe(3)
		t.expect(g.phase).toBe("ready")
		stepsUntilChange(g)
		Game.died(g)
		t.expect(#Game.died(g)).toBe(0) -- already dying
		t.expect(#Game.cleared(g)).toBe(0)
		t.expect(g.lives).toBe(2)
	end)

	it("a death or a clear during the level-clear pause or after game over does nothing", function()
		local g = Game.new(SMALL)
		stepsUntilChange(g)
		Game.cleared(g)
		t.expect(g.phase).toBe("levelclear")
		local timer = g.timer
		t.expect(#Game.died(g)).toBe(0)
		t.expect(#Game.cleared(g)).toBe(0)
		t.expect(g.phase).toBe("levelclear")
		t.expect(g.lives).toBe(3)
		t.expect(g.level).toBe(1)
		t.expect(g.timer).toBe(timer)
		-- and after the last life
		local h = Game.new(SMALL)
		for _ = 1, 3 do
			stepsUntilChange(h) -- into play
			Game.died(h)
			stepsUntilChange(h) -- the death pause: the next attempt, or game over
		end
		t.expect(h.phase).toBe("gameover")
		t.expect(#Game.died(h)).toBe(0)
		t.expect(#Game.cleared(h)).toBe(0)
		t.expect(h.phase).toBe("gameover")
		t.expect(h.lives).toBe(0)
		t.expect(h.level).toBe(1)
	end)

	it("clearing the maze pauses, then the next level starts with a Ready for it", function()
		local g = Game.new(SMALL)
		stepsUntilChange(g)
		local events = Game.cleared(g)
		t.expect(kinds(events)).toEqual({ "LevelCleared" })
		t.expect(events[1].level).toBe(1)
		t.expect(g.phase).toBe("levelclear")
		t.expect(g.timer).toBe(4)
		local n, after = stepsUntilChange(g)
		t.expect(n).toBe(4)
		t.expect(kinds(after)).toEqual({ "Ready" })
		t.expect(after[1].reason).toBe("level")
		t.expect(after[1].level).toBe(2)
		t.expect(g.level).toBe(2)
		t.expect(g.phase).toBe("ready")
		t.expect(g.lives).toBe(3) -- lives carry over
	end)

	it("the score adds up, and the first time it reaches 10,000 it earns one extra life", function()
		local g = Game.new(SMALL)
		t.expect(#Game.addScore(g, 9980)).toBe(0)
		t.expect(g.score).toBe(9980)
		local events = Game.addScore(g, 10)
		t.expect(#events).toBe(0)
		events = Game.addScore(g, 10) -- exactly 10,000
		t.expect(kinds(events)).toEqual({ "ExtraLife" })
		t.expect(events[1].lives).toBe(4)
		t.expect(g.lives).toBe(4)
		t.expect(#Game.addScore(g, 15000)).toBe(0) -- never a second one
		t.expect(g.lives).toBe(4)
		t.expect(g.score).toBe(25000)
	end)

	it("an extra life is earned by jumping past 10,000 too", function()
		local g = Game.new(SMALL)
		Game.addScore(g, 9990)
		local events = Game.addScore(g, 50)
		t.expect(kinds(events)).toEqual({ "ExtraLife" })
		t.expect(g.score).toBe(10040)
		t.expect(g.lives).toBe(4)
	end)

	it("with extraLifeScore 0 there is never an extra life", function()
		local g = Game.new({
			lives = 3,
			extraLifeScore = 0,
			readyTicks = 0,
			dyingTicks = 0,
			levelClearTicks = 0,
			tickRate = 30,
		})
		t.expect(#Game.addScore(g, 99999)).toBe(0)
		t.expect(g.lives).toBe(3)
	end)

	it("playAgain starts a fresh run, but only after gameover", function()
		local g = Game.new(SMALL)
		local events, ok = Game.playAgain(g)
		t.expect(ok).toBe(false)
		t.expect(#events).toBe(0)
		stepsUntilChange(g)
		_, ok = Game.playAgain(g)
		t.expect(ok).toBe(false) -- not over yet
		Game.addScore(g, 10040) -- earns the extra life: four lives to lose
		for _ = 1, 4 do
			Game.died(g)
			stepsUntilChange(g)
			if g.phase == "ready" then
				stepsUntilChange(g)
			end
		end
		t.expect(g.phase).toBe("gameover")
		local again, done = Game.playAgain(g)
		t.expect(done).toBe(true)
		t.expect(kinds(again)).toEqual({ "Ready" })
		t.expect(again[1].reason).toBe("again")
		t.expect(g.phase).toBe("ready")
		t.expect(g.timer).toBe(3)
		t.expect(g.level).toBe(1)
		t.expect(g.score).toBe(0)
		t.expect(g.lives).toBe(3)
		-- the extra life can be earned again in the new run
		t.expect(kinds(Game.addScore(g, 10000))).toEqual({ "ExtraLife" })
	end)

	it("with no pauses a death respawns on the next step and the run never waits in ready", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.died(g)
		t.expect(g.phase).toBe("dying")
		local events = Game.step(g)
		t.expect(kinds(events)).toEqual({ "Ready" })
		t.expect(g.phase).toBe("playing")
		t.expect(g.lives).toBe(2)
	end)

	it("rejects rules that make no sense", function()
		local function with(field: string, value: number): Game.Config
			local c: any = table.clone(Game.CLASSIC_CONFIG)
			c[field] = value
			return c
		end
		for _, bad in
			{
				with("lives", 0),
				with("lives", 1.5),
				with("extraLifeScore", -1),
				with("readyTicks", -1),
				with("dyingTicks", 2.5),
				with("levelClearTicks", -3),
				with("tickRate", 0),
			}
		do
			t.expect(function()
				Game.new(bad)
			end).toThrow()
		end
	end)
end)
