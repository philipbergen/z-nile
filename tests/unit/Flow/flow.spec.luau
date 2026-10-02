--!strict
-- Flow: cases beyond the acceptance specs.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local t = require("@tests/lib/t")

local function play(phase: string, timer: number): any
	return { phase = phase, level = 2, score = 120, lives = 1, timer = timer, frightened = 0 }
end

return t.spec("Flow extras", function(it)
	it("every phase gets a fresh overlay with all three always-present fields", function()
		for _, phase in { "ready", "playing", "dying", "levelclear", "gameover" } do
			local o = Flow.overlay(play(phase, 10), Game.CLASSIC_CONFIG)
			t.expect(type(o.fade)).toBe("number")
			t.expect(type(o.flash)).toBe("boolean")
			t.expect(type(o.playAgain)).toBe("boolean")
		end
	end)

	it("half way through a classic dying pause the fade is half of FADE_MAX", function()
		t.expect(Flow.overlay(play("dying", 22.5), Game.CLASSIC_CONFIG).fade).toBeNear(0.3, 1e-9)
	end)

	it("the play-again keys can't be changed", function()
		t.expect(function()
			(Flow.PLAY_AGAIN_KEYS :: any)[1] = "Space"
		end).toThrow()
	end)
end)
