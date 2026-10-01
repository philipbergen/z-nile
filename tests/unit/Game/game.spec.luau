--!strict
-- Game: a one-life run, beyond the acceptance state-machine cases.
local Game = require("@logic/Game")
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

	it("adding score leaves the run's phase alone", function()
		local g = Game.new(Game.IMMEDIATE_CONFIG)
		Game.addScore(g, 10)
		t.expect(g.phase).toBe("playing")
		t.expect(g.score).toBe(10)
	end)
end)
