--!strict
-- f0170 AC5: the session configs. The default has no pauses, so a session that never asks for a run
-- behaves as before; GAME_CONFIG is the real thing. A speed that is too fast for the later levels is
-- refused up front.
local Game = require("@logic/Game")
local Maze = require("@logic/Maze")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

local CORRIDOR = Maze.parse({ "###############", "#            P#", "###############" }, "corridor")

return t.spec("f0170 session configs", function(it)
	it("the default config has no pauses: the run is in play from the start", function()
		local s = Session.new(CORRIDOR, 1)
		Session.join(s, "p")
		local play = Session.frame(s, "p").play
		t.expect(play.phase).toBe("playing")
		t.expect(play.lives).toBe(3)
		t.expect(play.timer).toBe(0)
		t.expect(Session.DEFAULT_CONFIG.movement).toEqual({ speed = 30, turnBufferTicks = 24 })
	end)

	it("GAME_CONFIG is the classic rules and starts with the ready countdown", function()
		t.expect(Session.GAME_CONFIG.play).toEqual(Game.CLASSIC_CONFIG)
		t.expect(Session.GAME_CONFIG.movement).toEqual({ speed = 30, turnBufferTicks = 24 })
		t.expect(Session.GAME_CONFIG.maxIntentsPerTick).toBe(4)
		local s = Session.new(CORRIDOR, 1, Session.GAME_CONFIG)
		Session.join(s, "p")
		t.expect(Session.frame(s, "p").play.phase).toBe("ready")
		t.expect(Session.frame(s, "p").play.timer).toBe(60)
	end)

	it("a config without a play record means no pauses, however the rest is set", function()
		local s = Session.new(
			CORRIDOR,
			1,
			{ movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 2 }
		)
		Session.join(s, "p")
		t.expect(Session.frame(s, "p").play.phase).toBe("playing")
	end)

	it(
		"level speeds scale the base speed, so the base may not be so fast that a later level would cross two tiles",
		function()
			-- 96 * 1.25 = 120 units is one whole tile per tick: the most a step may cover
			Session.new(
				CORRIDOR,
				1,
				{ movement = { speed = 96, turnBufferTicks = 24 }, maxIntentsPerTick = 4 }
			)
			t.expect(function()
				Session.new(
					CORRIDOR,
					1,
					{ movement = { speed = 97, turnBufferTicks = 24 }, maxIntentsPerTick = 4 }
				)
			end).toThrow("too fast")
			t.expect(function()
				Session.new(
					CORRIDOR,
					1,
					{ movement = { speed = 120, turnBufferTicks = 24 }, maxIntentsPerTick = 4 }
				)
			end).toThrow("level")
		end
	)

	it(
		"a play config whose tick rate is not the session's is refused: the frightened time would be rescaled",
		function()
			local movement = { speed = 30, turnBufferTicks = 24 }
			local ok: Game.Config = table.clone(Game.CLASSIC_CONFIG)
			Session.new(CORRIDOR, 1, { movement = movement, maxIntentsPerTick = 4, play = ok }) -- 30: fine
			for _, rate in { 60, 29, 31, 1 } do
				local off: Game.Config = table.clone(Game.CLASSIC_CONFIG)
				off.tickRate = rate
				t.expect(function()
					Session.new(CORRIDOR, 1, { movement = movement, maxIntentsPerTick = 4, play = off })
				end).toThrow("tickRate")
			end
		end
	)

	it("bad rules are refused when a player joins", function()
		local bad: any = table.clone(Game.CLASSIC_CONFIG)
		bad.lives = 0
		local s = Session.new(
			CORRIDOR,
			1,
			{ movement = { speed = 30, turnBufferTicks = 24 }, maxIntentsPerTick = 4, play = bad }
		)
		t.expect(function()
			Session.join(s, "p")
		end).toThrow("lives")
	end)
end)
