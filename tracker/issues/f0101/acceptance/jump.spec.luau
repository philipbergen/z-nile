--!strict
-- f0101 AC1: the spy hop's timing, pure and counted in steps (Session.STEP_RATE a second), so the server and the
-- camera agree on it. Hop.canStart says whether a hop may start at a step, given when the last one started;
-- Hop.rise is how far the eye is above its standing height: a parabola that rises to Hop.RISE half way through
-- Hop.TICKS and lands at 0. The next hop may start Hop.COOLDOWN steps after landing. Hop.airborne is a rise over
-- Hop.CLEARANCE, the eye above the wall tops: the middle of the hop.
local Hop = require("@logic/Hop")
local Session = require("@logic/Session")
local t = require("@tests/lib/t")

return t.spec("f0101 jump", function(it)
	it(
		"has the designed numbers: up 14 studs and down again in 0.8 s, then at least 0.5 s before the next",
		function()
			t.expect(Hop.RISE).toBe(14)
			t.expect(Hop.TICKS).toBe(12)
			t.expect(Hop.TICKS / Session.STEP_RATE).toBeNear(0.8, 1e-9)
			t.expect(Hop.COOLDOWN).toBe(8)
			t.expect(Hop.COOLDOWN / Session.STEP_RATE >= 0.5).toBe(true)
			t.expect((Hop.COOLDOWN - 1) / Session.STEP_RATE < 0.5).toBe(true) -- the shortest whole number of steps
		end
	)

	it("the first hop may always start", function()
		t.expect(Hop.canStart(nil, 0)).toBe(true)
		t.expect(Hop.canStart(nil, 12345)).toBe(true)
	end)

	it("no new hop while one is up, or before the cool-down after it lands has passed", function()
		local last = 100
		for dt = 0, Hop.TICKS + Hop.COOLDOWN - 1 do
			t.expect(Hop.canStart(last, last + dt)).toBe(false)
		end
		t.expect(Hop.canStart(last, last + Hop.TICKS + Hop.COOLDOWN)).toBe(true)
		t.expect(Hop.canStart(last, last + 500)).toBe(true)
	end)

	it(
		"a step that is not finite never starts a hop; a last start that is not finite does not block one",
		function()
			t.expect(Hop.canStart(nil, 0 / 0)).toBe(false)
			t.expect(Hop.canStart(nil, math.huge)).toBe(false)
			t.expect(Hop.canStart(0 / 0, 3)).toBe(true)
			t.expect(Hop.canStart(-math.huge, 3)).toBe(true)
		end
	)

	it("the eye is at the top, Hop.RISE up, half way through, and on the ground at both ends", function()
		local last = 10
		t.expect(Hop.rise(last, last)).toBe(0)
		t.expect(Hop.rise(last, last + Hop.TICKS / 2)).toBeNear(Hop.RISE, 1e-9)
		t.expect(Hop.rise(last, last + Hop.TICKS)).toBe(0)
	end)

	it("it is a parabola: symmetric, and three quarters up a quarter of the way through", function()
		local last = 3
		for _, u in { 0.1, 0.25, 0.4 } do
			local up = Hop.rise(last, last + u * Hop.TICKS)
			local down = Hop.rise(last, last + (1 - u) * Hop.TICKS)
			t.expect(up).toBeNear(down, 1e-9)
			t.expect(up).toBeNear(Hop.RISE * 4 * u * (1 - u), 1e-9)
		end
		t.expect(Hop.rise(last, last + 0.25 * Hop.TICKS)).toBeNear(0.75 * Hop.RISE, 1e-9)
	end)

	it("it rises and then falls between steps too, never below the ground or above the top", function()
		local prev = 0
		local peaked = false
		for i = 1, 119 do
			local h = Hop.rise(0, i / 10)
			t.expect(h > 0 and h <= Hop.RISE + 1e-9).toBe(true)
			if h < prev then
				peaked = true
			else
				t.expect(peaked).toBe(false)
			end
			prev = h
		end
		t.expect(peaked).toBe(true)
	end)

	it("no hop, before it starts, after it lands, or at a time that is not finite: 0", function()
		t.expect(Hop.rise(nil, 5)).toBe(0)
		t.expect(Hop.rise(5, 4.9)).toBe(0)
		t.expect(Hop.rise(5, 5 + Hop.TICKS + 0.1)).toBe(0)
		t.expect(Hop.rise(5, 0 / 0)).toBe(0)
		t.expect(Hop.rise(0 / 0, 5)).toBe(0)
		t.expect(Hop.rise(5, math.huge)).toBe(0)
	end)

	it(
		"airborne is the eye over the wall tops: steps 2 to 10 of the hop, 0.6 s, never at take-off or landing",
		function()
			local last = 40
			local window = {}
			for dt = -1, Hop.TICKS + 1 do
				local up = Hop.airborne(last, last + dt)
				t.expect(up).toBe(Hop.rise(last, last + dt) > Hop.CLEARANCE)
				if up then
					table.insert(window, dt)
				end
			end
			t.expect(table.concat(window, ",")).toBe("2,3,4,5,6,7,8,9,10")
			t.expect(#window / Session.STEP_RATE).toBeNear(0.6, 1e-9)
			t.expect(Hop.airborne(nil, last)).toBe(false)
			t.expect(Hop.airborne(last, 0 / 0)).toBe(false)
		end
	)
end)
