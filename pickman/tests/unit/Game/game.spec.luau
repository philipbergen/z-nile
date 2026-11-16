--!strict
-- Game: a one-life run, beyond the acceptance state-machine cases.
local Game = require("@logic/Game")
local Levels = require("@logic/Levels")
local t = require("@tests/lib/t")

return t.spec("Game extras", function(it)
	it("a one-life run ends at the first death", function()
		local g = Game.new({
			lives = 1,
			extraLifeScore = 0,
			readyTicks = 0,
			dyingTicks = 1,
			levelClearTicks = 0,
			tickRate = 30,
		})
		t.expect(g.phase).toBe("playing")
		Game.died(g)
		t.expect(g.lives).toBe(0)
		local events = Game.step(g)
		t.expect(events[1].kind).toBe("GameOver")
		t.expect(g.phase).toBe("gameover")
	end)

	it("a power pellet starts the level's frightened period and it runs out", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		local events = Game.power(g)
		t.expect(events[1].kind).toBe("PowerStarted")
		t.expect(g.frightened).toBe(180)
		for _ = 1, 179 do
			t.expect(#Game.step(g)).toBe(0)
		end
		t.expect(Game.step(g)[1].kind).toBe("PowerEnded")
		t.expect(g.frightened).toBe(0)
	end)

	it("adding score leaves the run's phase alone", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.addScore(g, 10)
		t.expect(g.phase).toBe("playing")
		t.expect(g.score).toBe(10)
	end)

	it("points are multiplied by the level with a ramp and left alone without", function()
		local classic = Game.new(Game.IMMEDIATE_CONFIG)
		classic.level = 3
		t.expect(Game.points(classic, 200)).toBe(200)
		local ramped = Game.new(Game.IMMEDIATE_CONFIG, Levels.RAMP)
		ramped.level = 3
		t.expect(Game.points(ramped, 200)).toBe(600)
	end)

	it("the extra life is the threshold times the run's start level, and a new run starts there", function()
		local g = Game.new({
			lives = 3,
			extraLifeScore = 100,
			readyTicks = 0,
			dyingTicks = 1,
			levelClearTicks = 0,
			tickRate = 30,
		})
		t.expect(g.start).toBe(1)
		g.start = 2
		g.level = 4
		Game.addScore(g, 150)
		t.expect(g.lives).toBe(3)
		Game.addScore(g, 60)
		t.expect(g.lives).toBe(4)
		g.phase = "gameover"
		Game.playAgain(g)
		t.expect(g.level).toBe(2)
	end)

	it("a run can start on a later level", function()
		local g = Game.new(nil, nil, 4)
		t.expect(g.level).toBe(4)
		t.expect(g.start).toBe(4)
		t.expect(function()
			Game.new(nil, nil, 0)
		end).toThrow("start")
		t.expect(function()
			Game.new(nil, nil, 1.5)
		end).toThrow("start")
	end)
end)
