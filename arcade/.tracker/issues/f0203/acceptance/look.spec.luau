--!strict
-- f0203 AC4: arcade's first-person Look (free look, the arrows' look and spring, the eased turn, snapshot blending).
local Look = require("@logic/Look")
local t = require("@tests/lib/t")

local PI = math.pi
local E = 1e-9

local function near(l: Look.Look, yaw: number, pitch: number)
	t.expect(l.yaw).toBeNear(yaw, E)
	t.expect(l.pitch).toBeNear(pitch, E)
end

local function held(dirs: { Look.Dir }): Look.Arrows
	local a = Look.arrows()
	for _, d in dirs do
		a = Look.press(a, d :: Look.Dir, true)
	end
	return a
end

return t.spec("f0203 Look", function(it)
	it("the defaults are pickman's: 0.004 rad a pixel, 80 degrees of pitch, 0.12 s a quarter turn", function()
		t.expect(Look.DEFAULT)
			.toEqual({ radiansPerPixel = 0.004, maxPitch = math.rad(80), turnSeconds = 0.12 })
		t.expect(table.isfrozen(Look.DEFAULT)).toBe(true)
		t.expect(Look.rate()).toBeNear((PI / 2) / 0.12, E)
		t.expect(Look.rate(Look.tune({ turnSeconds = 0.24 }))).toBeNear((PI / 2) / 0.24, E)
	end)

	it("wrap keeps an angle in (-pi, pi]", function()
		t.expect(Look.wrap(PI)).toBe(PI)
		t.expect(Look.wrap(-PI)).toBe(PI)
		t.expect(Look.wrap(0)).toBe(0)
		t.expect(Look.wrap(3 * PI / 2)).toBeNear(-PI / 2, E)
		t.expect(Look.wrap(-4 * PI + 0.1)).toBeNear(0.1, E)
	end)

	it("approach goes the short way round, by at most its step, and lands on the target", function()
		t.expect(Look.approach(3, -3, 0.1)).toBeNear(3.1, E)
		t.expect(Look.approach(-3, 3, 0.1)).toBeNear(-3.1, E)
		t.expect(Look.approach(0.5, 0.55, 0.1)).toBeNear(0.55, E)
		t.expect(Look.approach(0, 1, 0.25)).toBeNear(0.25, E)
	end)

	it(
		"the eased turn moves a quarter turn in turnSeconds, starts at the target, and is frame-rate independent",
		function()
			t.expect(Look.ease(nil, PI / 2, 0.016)).toBeNear(PI / 2, E)
			t.expect(Look.ease(0, PI / 2, 0.06)).toBeNear(PI / 4, E)
			t.expect(Look.ease(0, PI / 2, 0.12)).toBeNear(PI / 2, E)
			t.expect(Look.ease(0, PI / 2, 1)).toBeNear(PI / 2, E)
			local half = Look.ease(Look.ease(0, PI, 0.03), PI, 0.03)
			t.expect(half).toBeNear(Look.ease(0, PI, 0.06), E)
			t.expect(Look.ease(0, PI / 2, 0.06, Look.tune({ turnSeconds = 0.24 }))).toBeNear(PI / 8, E)
			for _, dt in { 0, -1, 0 / 0, math.huge } do
				t.expect(Look.ease(0.3, PI / 2, dt)).toBeNear(0.3, E)
			end
		end
	)

	it("the mouse turns right for a drag right and looks down for a drag down, at radiansPerPixel", function()
		near(Look.mouse({ yaw = 0, pitch = 0 }, 100, 0), -0.4, 0)
		near(Look.mouse({ yaw = 0, pitch = 0 }, 0, 100), 0, -0.4)
		near(Look.mouse({ yaw = 0, pitch = 0 }, -50, -25, Look.tune({ radiansPerPixel = 0.01 })), 0.5, 0.25)
		near(Look.mouse({ yaw = 3, pitch = 0 }, -100, 0), Look.wrap(3.4), 0)
	end)

	it("pitch stops at maxPitch either way", function()
		near(Look.mouse({ yaw = 0, pitch = 0 }, 0, -100000), 0, math.rad(80))
		near(Look.mouse({ yaw = 0, pitch = 0 }, 0, 100000), 0, -math.rad(80))
		near(Look.turn({ yaw = 0, pitch = 0 }, 0, 5, Look.tune({ maxPitch = 0.5 })), 0, 0.5)
	end)

	it("turn adds radians (yaw left, pitch up) and wraps the yaw", function()
		near(Look.turn({ yaw = 0.2, pitch = 0.1 }, 0.3, -0.2), 0.5, -0.1)
		near(Look.turn({ yaw = 3, pitch = 0 }, 0.5, 0), Look.wrap(3.5), 0)
	end)

	it("a mouse step or a turn that is not a number leaves the look as it was", function()
		local l = { yaw = 0.3, pitch = -0.2 }
		near(Look.mouse(l, 0 / 0, 5), 0.3, -0.2)
		near(Look.mouse(l, 5, math.huge), 0.3, -0.2)
		near(Look.turn(l, 0 / 0, 0.1), 0.3, -0.2)
		near(Look.turn(l, 0.1, -math.huge), 0.3, -0.2)
	end)

	it("snap recentres, and the starting values are at rest", function()
		near(Look.snap(), 0, 0)
		t.expect(Look.rest()).toEqual({ look = { yaw = 0, pitch = 0 }, spring = false })
		t.expect(Look.arrows()).toEqual({ up = false, down = false, left = false, right = false })
	end)

	it("press sets or clears one arrow and leaves the given arrows alone", function()
		local a = Look.arrows()
		local b = Look.press(a, "left", true)
		t.expect(b).toEqual({ up = false, down = false, left = true, right = false })
		t.expect(a.left).toBe(false)
		t.expect(Look.press(b, "left", false)).toEqual(Look.arrows())
		t.expect(Look.press(b, nil, true)).toEqual(b)
		t.expect(Look.press(held({ "up", "right" }), "down", true))
			.toEqual({ up = true, down = true, left = false, right = true })
	end)

	it("the arrows look in quarter turns from the heading, positive left, two together between", function()
		t.expect(Look.quarters(Look.arrows())).toBe(nil)
		local cases: { { Look.Dir } } = {
			{ "up" },
			{ "left" },
			{ "right" },
			{ "down" },
			{ "up", "left" },
			{ "up", "right" },
			{ "down", "left" },
			{ "down", "right" },
			{ "left", "right" },
			{ "up", "down" },
			{ "up", "down", "left", "right" },
			{ "left", "right", "down" },
			{ "up", "down", "left" },
		}
		local want = { 0, 1, -1, 2, 0.5, -0.5, 1.5, -1.5, 0, 0, 0, 2, 1 }
		for i, c in cases do
			t.expect(Look.quarters(held(c))).toBe(want[i])
		end
	end)

	it(
		"held arrows turn the look toward them at the turn rate, level the pitch, and ignore other look input",
		function()
			local s = Look.spring(Look.rest(), { yaw = 0, pitch = 0 }, held({ "left" }), 0.06)
			near(s.look, PI / 4, 0)
			t.expect(s.spring).toBe(true)
			-- the mouse moved the look this frame: while an arrow is held it does not count
			s = Look.spring(s, { yaw = -1, pitch = 0.5 }, held({ "left" }), 0.06)
			near(s.look, PI / 2, 0)
			s = Look.spring(s, s.look, held({ "left" }), 0.5)
			near(s.look, PI / 2, 0)
			local level = { look = { yaw = 0, pitch = 0.5 }, spring = false }
			local p = Look.spring(level, { yaw = 0, pitch = 0.5 }, held({ "up" }), 0.02)
			near(p.look, 0, 0.5 - PI / 12)
			p = Look.spring(p, p.look, held({ "up" }), 0.06)
			near(p.look, 0, 0)
		end
	)

	it("let go, the look springs back to the heading at the same rate and then rests", function()
		local s = Look.spring(Look.rest(), { yaw = 0, pitch = 0 }, held({ "left" }), 0.12)
		near(s.look, PI / 2, 0)
		s = Look.spring(s, s.look, Look.arrows(), 0.06)
		near(s.look, PI / 4, 0)
		t.expect(s.spring).toBe(true)
		s = Look.spring(s, s.look, Look.arrows(), 0.06)
		near(s.look, 0, 0)
		t.expect(s.spring).toBe(false)
		s = Look.spring(s, s.look, Look.arrows(), 0.06)
		near(s.look, 0, 0)
		t.expect(s.spring).toBe(false)
	end)

	it("any other look input during the spring takes over from where it left the look", function()
		local s = Look.spring(Look.rest(), { yaw = 0, pitch = 0 }, held({ "right" }), 0.12)
		s = Look.spring(s, s.look, Look.arrows(), 0.03)
		t.expect(s.spring).toBe(true)
		local moved = Look.mouse(s.look, 10, 0)
		s = Look.spring(s, moved, Look.arrows(), 0.03)
		near(s.look, moved.yaw, moved.pitch)
		t.expect(s.spring).toBe(false)
		s = Look.spring(s, s.look, Look.arrows(), 0.5)
		near(s.look, moved.yaw, moved.pitch)
	end)

	it(
		"the arrows' look is frame-rate independent, and a dt that is not a positive number does not move it",
		function()
			local one = Look.spring(Look.rest(), { yaw = 0, pitch = 0 }, held({ "down", "left" }), 0.1)
			local a = Look.spring(Look.rest(), { yaw = 0, pitch = 0 }, held({ "down", "left" }), 0.05)
			a = Look.spring(a, a.look, held({ "down", "left" }), 0.05)
			near(a.look, one.look.yaw, one.look.pitch)
			for _, dt in { 0, -0.1, 0 / 0 } do
				local s = Look.spring(Look.rest(), { yaw = 0, pitch = 0 }, held({ "left" }), dt)
				near(s.look, 0, 0)
			end
		end
	)

	it("alpha is the share of a snapshot interval gone, clamped, and 1 when it is not a number", function()
		t.expect(Look.alpha(1 / 60, 30)).toBeNear(0.5, E)
		t.expect(Look.alpha(1, 30)).toBe(1)
		t.expect(Look.alpha(-1, 30)).toBe(0)
		t.expect(Look.alpha(0 / 0, 30)).toBe(1)
	end)

	it("blend goes between two values, and blendYaw goes the short way round", function()
		t.expect(Look.blend(0, 10, 0.25)).toBeNear(2.5, E)
		t.expect(Look.blend(0, 10, 2)).toBe(10)
		t.expect(Look.blend(0, 10, -1)).toBe(0)
		t.expect(Look.blend(0, 10, 0 / 0)).toBe(10)
		t.expect(Look.blendYaw(3, -3, 0.25)).toBeNear(3 + (2 * PI - 6) * 0.25, E)
		t.expect(Look.blendYaw(-3, 3, 0.5)).toBeNear(Look.wrap(-3 - (2 * PI - 6) * 0.5), E)
		t.expect(Look.blendYaw(0.2, 0.6, 0.5)).toBeNear(0.4, E)
	end)

	it("tune fills from the defaults, freezes, and refuses a tuning that cannot work", function()
		local x = Look.tune({ maxPitch = 1 })
		t.expect(x.maxPitch).toBe(1)
		t.expect(x.radiansPerPixel).toBe(0.004)
		t.expect(table.isfrozen(x)).toBe(true)
		t.expect(Look.tune()).toEqual(Look.DEFAULT)
		local bads: { { any } } = {
			{ "radiansPerPixel", 0 },
			{ "radiansPerPixel", 0 / 0 },
			{ "maxPitch", 0 },
			{ "maxPitch", 2 },
			{ "turnSeconds", 0 },
			{ "turnSeconds", -1 },
		}
		for _, bad in bads do
			local over: any = { [bad[1]] = bad[2] }
			t.expect(function()
				Look.tune(over)
			end).toThrow("Look.tune")
		end
	end)
end)
