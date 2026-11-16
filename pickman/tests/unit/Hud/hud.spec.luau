--!strict
-- Hud: cases beyond the acceptance specs.
local Hud = require("@logic/Hud")
local Touch = require("@logic/Touch")
local t = require("@tests/lib/t")

return t.spec("Hud extras", function(it)
	it("models a fresh run", function()
		local m = Hud.model({ phase = "ready", level = 1, score = 0, lives = 3, timer = 60, frightened = 0 })
		t.expect(m).toEqual({ score = "0", level = "LEVEL 1", lives = 3, power = 0 })
	end)

	it("lays out a 1280x720 screen with 32 px text", function()
		local l = Hud.layout(1280, 720)
		t.expect(l).toEqual({
			textSize = 32,
			margin = 16,
			iconSize = 32,
			barWidth = 320,
			barHeight = 13,
			safeX = 0,
			safeY = 0,
			safeW = 1280,
			safeH = 720,
		})
	end)

	it("caps the power bar at 400 px", function()
		t.expect(Hud.layout(3840, 2160).barWidth).toBe(400)
	end)

	it("the model shows picks out of the goal only when the frame has them", function()
		local play: any = { phase = "playing", level = 1, score = 0, lives = 3, timer = 60, frightened = 0 }
		t.expect(Hud.model(play).picks).toBe(nil)
		play.picks = 4
		play.picksGoal = 10
		t.expect(Hud.model(play).picks).toBe("PICKS 4/10")
	end)

	it("the picks box is the row under the score block, left-aligned and its size", function()
		local l = Hud.layout(844, 390)
		local score = Touch.blocks(l).score
		local b = Hud.picksBox(score)
		t.expect(b.x).toBe(score.x)
		t.expect(b.y >= score.y + score.h).toBe(true)
		t.expect(b.w).toBe(score.w)
	end)
end)
