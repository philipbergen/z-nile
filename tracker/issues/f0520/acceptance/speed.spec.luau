--!strict
-- f0520 AC1: the game runs at half speed in real time. The rules keep counting ticks (30 per game second),
-- but the server steps 15 times per real second, so everything in game time takes twice as long: the
-- level-1 player covers 3.75 tiles in one real second instead of 7.5, and the 24-tick turn buffer lasts
-- 1.6 s instead of 0.8 s.
local Maze = require("@logic/Maze")
local Movement = require("@logic/Movement")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

-- the spawn is at the east end (x = 13): a corridor long enough to walk for several real seconds
local CORRIDOR =
	Maze.parse({ string.rep("#", 62), "#" .. string.rep(" ", 59) .. "P#", string.rep("#", 62) }, "long")

-- steps taken in `seconds` of real time at `fps` frames a second, as the server's loop does it
local function stepsIn(seconds: number, fps: number): number
	local clock = Session.newClock(Session.STEP_RATE)
	local steps = 0
	for _ = 1, math.floor(seconds * fps + 0.5) do
		steps += Session.advance(clock, 1 / fps)
	end
	return steps
end

return t.spec("f0520 game speed", function(it)
	it("ticks per game second stay 30, and the game runs at half speed: 15 steps per real second", function()
		t.expect(Session.TICK_RATE).toBe(30)
		t.expect(Session.GAME_SPEED).toBe(0.5)
		t.expect(Session.STEP_RATE).toBe(15)
		t.expect(Session.STEP_RATE).toBe(Session.TICK_RATE * Session.GAME_SPEED)
	end)

	it("the clock at the step rate yields 15 steps a real second at any frame rate", function()
		for _, fps in { 30, 50, 60, 144 } do
			t.expect(stepsIn(1, fps)).toBe(15)
			t.expect(stepsIn(10, fps)).toBe(150)
		end
	end)

	it(
		"a plain newClock() is still 30 steps a second: the tick-pinned specs and tools are unchanged",
		function()
			t.expect(Session.newClock().rate).toBe(30)
			t.expect(Session.newClock(Session.STEP_RATE).rate).toBe(15)
		end
	)

	it("the level-1 player covers 3.75 tiles in one real second, not 7.5", function()
		local s = Session.new(CORRIDOR, 1)
		Session.join(s, "p")
		local clock = Session.newClock(Session.STEP_RATE)
		local before = Session.snapshot(s, "p").player.x
		for _ = 1, 60 do
			for _ = 1, Session.advance(clock, 1 / 60) do
				Session.step(s)
			end
		end
		t.expect(before - Session.snapshot(s, "p").player.x).toBeNear(3.75, 1e-9)
		-- and over four real seconds, 15 tiles
		for _ = 1, 180 do
			for _ = 1, Session.advance(clock, 1 / 60) do
				Session.step(s)
			end
		end
		t.expect(before - Session.snapshot(s, "p").player.x).toBeNear(15, 1e-9)
	end)

	it("the turn buffer lasts 1.6 real seconds: 24 ticks at 15 steps a second", function()
		t.expect(Movement.DEFAULT_CONFIG.turnBufferTicks / Session.STEP_RATE).toBeNear(1.6, 1e-9)
	end)
end)
