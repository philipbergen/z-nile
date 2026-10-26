--!strict
-- f0143 AC1: Logic/Boost, the speed boost counted in steps. A boost starts at a step and lasts Boost.TICKS steps
-- (the starting step included); the next may start Boost.TICKS + Boost.COOLDOWN steps after the last started. A
-- boosted step covers round(speed * FACTOR) units, never more than the cap (a tile a step). The double tap is a
-- client fold over real seconds: two forward presses within WINDOW pair once; a triple tap pairs once; a press at
-- a non-finite or earlier time never pairs. The camera widens by FOV degrees, ramped over RAMP steps at each end.
-- On every level a boost gains at least two tiles on a hunting ghost (the measurable proxy for "enough to pull
-- away from a chasing ghost").
local Boost = require("@logic/Boost")
local Levels = require("@logic/Levels")
local Movement = require("@logic/Movement")
local t = require("@tests/lib/t")

local NAN = 0 / 0

return t.spec("f0143 Boost", function(it)
	it("the constants and the wire string", function()
		t.expect(Boost.INTENT).toBe("Boost")
		t.expect(Boost.FACTOR).toBe(1.5)
		t.expect(Boost.TICKS).toBe(22)
		t.expect(Boost.COOLDOWN).toBe(90)
		t.expect(Boost.WINDOW).toBe(0.3)
		t.expect(Boost.FOV).toBe(8)
		t.expect(Boost.RAMP).toBe(2)
		t.expect(Boost.isIntent("Boost")).toBe(true)
		for _, v in { "boost", "BOOST", "Boost ", "Hop", "Forward", 1, true, { "Boost" } } :: { any } do
			t.expect(Boost.isIntent(v)).toBe(false)
		end
		t.expect(Boost.isIntent(nil)).toBe(false)
	end)

	it("canStart: never blocked before the first, blocked for TICKS + COOLDOWN steps, never for a non-finite tick", function()
		t.expect(Boost.canStart(nil, 0)).toBe(true)
		t.expect(Boost.canStart(NAN, 5)).toBe(true)
		t.expect(Boost.canStart(100, 100)).toBe(false)
		t.expect(Boost.canStart(100, 100 + Boost.TICKS + Boost.COOLDOWN - 1)).toBe(false)
		t.expect(Boost.canStart(100, 100 + Boost.TICKS + Boost.COOLDOWN)).toBe(true)
		t.expect(Boost.canStart(nil, NAN)).toBe(false)
		t.expect(Boost.canStart(nil, math.huge)).toBe(false)
	end)

	it("active: the starting step and the next TICKS - 1, nothing before or after, nothing for nil or non-finite", function()
		t.expect(Boost.active(nil, 10)).toBe(false)
		t.expect(Boost.active(10, 9)).toBe(false)
		t.expect(Boost.active(10, 10)).toBe(true)
		t.expect(Boost.active(10, 10 + Boost.TICKS - 1)).toBe(true)
		t.expect(Boost.active(10, 10 + Boost.TICKS)).toBe(false)
		t.expect(Boost.active(NAN, 10)).toBe(false)
		t.expect(Boost.active(10, NAN)).toBe(false)
	end)

	it("speed: FACTOR rounded, capped, unchanged when inactive", function()
		t.expect(Boost.speed(30, true, 120)).toBe(45)
		t.expect(Boost.speed(35, true, 120)).toBe(53) -- 52.5 rounds up
		t.expect(Boost.speed(33, true, 120)).toBe(50) -- 49.5 rounds up, never truncates
		t.expect(Boost.speed(30, false, 120)).toBe(30)
		t.expect(Boost.speed(100, true, 120)).toBe(120)
		t.expect(Boost.speed(80, true, 120)).toBe(120)
	end)

	it("status: boosting, then cooling, then ready", function()
		t.expect(Boost.status(nil, 0)).toBe("ready")
		t.expect(Boost.status(10, 10)).toBe("boosting")
		t.expect(Boost.status(10, 10 + Boost.TICKS - 1)).toBe("boosting")
		t.expect(Boost.status(10, 10 + Boost.TICKS)).toBe("cooling")
		t.expect(Boost.status(10, 10 + Boost.TICKS + Boost.COOLDOWN - 1)).toBe("cooling")
		t.expect(Boost.status(10, 10 + Boost.TICKS + Boost.COOLDOWN)).toBe("ready")
	end)

	it("tap: two presses within WINDOW pair once; a slow second press restarts; a triple tap pairs once; a non-finite or earlier press never pairs", function()
		local taps = Boost.taps()
		t.expect(taps.last).toBe(nil)
		local fired
		taps, fired = Boost.tap(taps, 10)
		t.expect(fired).toBe(false)
		taps, fired = Boost.tap(taps, 10 + Boost.WINDOW)
		t.expect(fired).toBe(true) -- exactly the window still pairs
		t.expect(taps.last).toBe(nil)
		-- a slow second press is a new first press
		taps = Boost.taps()
		taps, fired = Boost.tap(taps, 20)
		taps, fired = Boost.tap(taps, 20 + Boost.WINDOW + 0.01)
		t.expect(fired).toBe(false)
		taps, fired = Boost.tap(taps, 20 + Boost.WINDOW + 0.2)
		t.expect(fired).toBe(true)
		-- a triple tap pairs once
		taps = Boost.taps()
		local n = 0
		for i = 0, 2 do
			taps, fired = Boost.tap(taps, 30 + i * 0.1)
			if fired then
				n += 1
			end
		end
		t.expect(n).toBe(1)
		-- a press at a non-finite or earlier time never pairs, and is not remembered
		taps = Boost.taps()
		taps, fired = Boost.tap(taps, 40)
		taps, fired = Boost.tap(taps, NAN)
		t.expect(fired).toBe(false)
		t.expect(taps.last).toBe(nil)
		taps, fired = Boost.tap(taps, 40.1)
		t.expect(fired).toBe(false)
		taps, fired = Boost.tap(taps, 40.0)
		t.expect(fired).toBe(false) -- earlier than the remembered press: a clock that went back
		t.expect(taps.last).toBe(nil)
	end)

	it("fov: ramps up over RAMP steps, holds FOV, ramps down to 0 at TICKS, 0 outside", function()
		t.expect(Boost.fov(nil, 5)).toBe(0)
		t.expect(Boost.fov(10, 9.5)).toBe(0)
		t.expect(Boost.fov(10, 10)).toBe(0)
		t.expect(Boost.fov(10, 11)).toBe(Boost.FOV / 2)
		t.expect(Boost.fov(10, 12)).toBe(Boost.FOV)
		t.expect(Boost.fov(10, 10 + Boost.TICKS / 2)).toBe(Boost.FOV)
		t.expect(Boost.fov(10, 10 + Boost.TICKS - 1)).toBe(Boost.FOV / 2)
		t.expect(Boost.fov(10, 10 + Boost.TICKS)).toBe(0)
		t.expect(Boost.fov(10, NAN)).toBe(0)
	end)

	it("on every level, a boost gains at least two tiles on a hunting ghost and stays within a tile a step, frightened too", function()
		for level = 1, Levels.COUNT do
			for _, frightened in { false, true } do
				local speed = Levels.playerSpeed(30, level, frightened)
				local boosted = Boost.speed(speed, true, Movement.UNITS)
				t.expect(boosted <= Movement.UNITS).toBe(true)
				t.expect(boosted > speed).toBe(true)
				local ghost = Levels.ghostSpeed(30, level, "normal")
				t.expect((boosted - ghost) * Boost.TICKS >= 2 * Movement.UNITS).toBe(true)
			end
		end
	end)
end)
