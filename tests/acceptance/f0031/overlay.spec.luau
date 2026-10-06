--!strict
-- f0300 AC1: Flow.overlay turns the replicated play record into what the screen shows over the maze:
-- READY! with the level in a ready pause, a fade that deepens through the dying pause and holds at game
-- over, the walls flashing through the level-clear pause, and GAME OVER with the final score and level.
-- Narrowed by c0063: what game over offers next (once PLAY AGAIN) is f0065's, not pinned here.
local Flow = require("@logic/Flow")
local Game = require("@logic/Game")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local RULES = Game.CLASSIC_CONFIG -- ready 60, dying 45, level clear 60

local function play(over: { [string]: any }?): Session.PlayFrame
	local p: any = { phase = "playing", level = 1, score = 0, lives = 3, timer = 0, frightened = 0 }
	local changes: { [string]: any } = over or {}
	for k, v in changes do
		p[k] = v
	end
	return p
end

local function overlay(over: { [string]: any }?, rules: Game.Config?): Flow.Overlay
	return Flow.overlay(play(over), rules or RULES)
end

return t.spec("f0300 Flow.overlay", function(it)
	it("the constants: fade up to 0.6, walls flash in runs of 6 ticks", function()
		t.expect(Flow.FADE_MAX).toBe(0.6)
		t.expect(Flow.FLASH_TICKS).toBe(6)
	end)

	it("a ready pause shows READY! over the level, with no fade or flash", function()
		for _, timer in { 60, 30, 1 } do
			local o = overlay({ phase = "ready", timer = timer, level = 3 })
			t.expect(o.banner).toBe("READY!")
			t.expect(o.detail).toBe("LEVEL 3")
			t.expect(o.fade).toBe(0)
			t.expect(o.flash).toBe(false)
		end
	end)

	it("play shows nothing over the maze", function()
		local o = overlay({ phase = "playing", score = 990, frightened = 40 })
		t.expect(o.banner).toBe(nil)
		t.expect(o.detail).toBe(nil)
		t.expect(o.fade).toBe(0)
		t.expect(o.flash).toBe(false)
	end)

	it("the fade deepens through the dying pause, from none to FADE_MAX", function()
		t.expect(overlay({ phase = "dying", timer = 45 }).fade).toBe(0)
		t.expect(overlay({ phase = "dying", timer = 15 }).fade).toBeNear(0.4, 1e-9)
		t.expect(overlay({ phase = "dying", timer = 0 }).fade).toBeNear(0.6, 1e-9)
		local last = -1
		for timer = 45, 0, -1 do
			local f = overlay({ phase = "dying", timer = timer }).fade
			t.expect(f > last).toBe(true)
			last = f
		end
	end)

	it("the fade follows the rules' dying pause, not a fixed one", function()
		local short: Game.Config = table.clone(RULES) :: any
		short.dyingTicks = 10
		t.expect(overlay({ phase = "dying", timer = 5 }, short).fade).toBeNear(0.3, 1e-9)
	end)

	it("with no dying pause a dying frame is fully faded, not an error", function()
		local none: Game.Config = table.clone(RULES) :: any
		none.dyingTicks = 0
		t.expect(overlay({ phase = "dying", timer = 0 }, none).fade).toBe(0.6)
	end)

	it("dying shows no banner", function()
		local o = overlay({ phase = "dying", timer = 20 })
		t.expect(o.banner).toBe(nil)
		t.expect(o.detail).toBe(nil)
		t.expect(o.flash).toBe(false)
	end)

	it("the walls are lit when (timer // FLASH_TICKS) is odd in the level-clear pause", function()
		t.expect(overlay({ phase = "levelclear", timer = 60 }).flash).toBe(false)
		t.expect(overlay({ phase = "levelclear", timer = 59 }).flash).toBe(true)
		t.expect(overlay({ phase = "levelclear", timer = 54 }).flash).toBe(true)
		t.expect(overlay({ phase = "levelclear", timer = 53 }).flash).toBe(false)
		t.expect(overlay({ phase = "levelclear", timer = 47 }).flash).toBe(true)
		t.expect(overlay({ phase = "levelclear", timer = 1 }).flash).toBe(false)
	end)

	it("a classic level-clear pause flashes five times, six ticks each", function()
		local runs, length, lit = {}, 0, false
		for timer = 60, 1, -1 do
			local now = overlay({ phase = "levelclear", timer = timer }).flash
			if now then
				length += 1
			elseif lit then
				table.insert(runs, length)
				length = 0
			end
			lit = now
		end
		t.expect(runs).toEqual({ 6, 6, 6, 6, 6 })
	end)

	it("the level-clear pause has no banner or fade", function()
		local o = overlay({ phase = "levelclear", timer = 59 })
		t.expect(o.banner).toBe(nil)
		t.expect(o.fade).toBe(0)
	end)

	it("only the level-clear pause flashes", function()
		for _, phase in { "ready", "playing", "dying", "gameover" } do
			for _, timer in { 59, 47, 7, 0 } do
				t.expect(overlay({ phase = phase, timer = timer }).flash).toBe(false)
			end
		end
	end)

	it("game over shows GAME OVER with the final score and level, fully faded", function()
		local o = overlay({ phase = "gameover", score = 12340, level = 3, lives = 0 })
		t.expect(o.banner).toBe("GAME OVER")
		t.expect(o.detail).toBe("SCORE 12340   LEVEL 3")
		t.expect(o.fade).toBe(0.6)
	end)

	it("leaves the record unchanged", function()
		local p = play({ phase = "gameover", score = 5 })
		local before = table.clone(p)
		Flow.overlay(p, RULES)
		t.expect(p).toEqual(before)
	end)
end)
