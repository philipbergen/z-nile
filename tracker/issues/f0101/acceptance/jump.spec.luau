--!strict
-- f0101 AC1: the spy hop's timing, pure and in real seconds. View.canJump says whether a jump may start now, given
-- when the last one started; View.jumpRise is how far the eye is above its standing height: a parabola that rises
-- to JUMP.rise half way through JUMP.seconds and lands at 0. The next jump may start JUMP.cooldown after landing.
local View = require("@logic/View")
local t = require("@tests/lib/t")

local J = View.JUMP

return t.spec("f0101 jump", function(it)
	it("has the designed numbers: up 14 studs and down again in 0.8 s, then 0.5 s before the next", function()
		t.expect(J.rise).toBe(14)
		t.expect(J.seconds).toBe(0.8)
		t.expect(J.cooldown).toBe(0.5)
		t.expect(function()
			(View.JUMP :: any).rise = 99
		end).toThrow()
	end)

	it("the first jump may always start", function()
		t.expect(View.canJump(nil, 0)).toBe(true)
		t.expect(View.canJump(nil, 12345.6)).toBe(true)
	end)

	it("no new jump while one is up, or before the cool-down after it lands has passed", function()
		local last = 100
		for _, dt in { 0, 0.01, 0.4, 0.79, 0.8, 1.0, 1.29 } do
			t.expect(View.canJump(last, last + dt)).toBe(false)
		end
		t.expect(View.canJump(last, last + J.seconds + J.cooldown)).toBe(true)
		t.expect(View.canJump(last, last + 5)).toBe(true)
	end)

	it(
		"a time that is not finite never starts a jump; a last start that is not finite does not block one",
		function()
			t.expect(View.canJump(nil, 0 / 0)).toBe(false)
			t.expect(View.canJump(nil, math.huge)).toBe(false)
			t.expect(View.canJump(0 / 0, 3)).toBe(true)
			t.expect(View.canJump(-math.huge, 3)).toBe(true)
		end
	)

	it("the eye is at the top, JUMP.rise up, half way through, and on the ground at both ends", function()
		local last = 10
		t.expect(View.jumpRise(last, last)).toBe(0)
		t.expect(View.jumpRise(last, last + J.seconds / 2)).toBeNear(J.rise, 1e-9)
		t.expect(View.jumpRise(last, last + J.seconds)).toBe(0)
	end)

	it("it is a parabola: symmetric, and three quarters up a quarter of the way through", function()
		local last = 3
		for _, u in { 0.1, 0.25, 0.4 } do
			local up = View.jumpRise(last, last + u * J.seconds)
			local down = View.jumpRise(last, last + (1 - u) * J.seconds)
			t.expect(up).toBeNear(down, 1e-9)
			t.expect(up).toBeNear(J.rise * 4 * u * (1 - u), 1e-9)
		end
		t.expect(View.jumpRise(last, last + 0.25 * J.seconds)).toBeNear(0.75 * J.rise, 1e-9)
	end)

	it("it rises and then falls, never below the ground or above the top", function()
		local last = 0
		local prev = 0
		local peaked = false
		for i = 1, 79 do
			local h = View.jumpRise(last, i / 100)
			t.expect(h > 0 and h <= J.rise + 1e-9).toBe(true)
			if h < prev then
				peaked = true
			else
				t.expect(peaked).toBe(false)
			end
			prev = h
		end
		t.expect(peaked).toBe(true)
	end)

	it("no jump, before it starts, after it lands, or at a time that is not finite: 0", function()
		t.expect(View.jumpRise(nil, 5)).toBe(0)
		t.expect(View.jumpRise(5, 4.9)).toBe(0)
		t.expect(View.jumpRise(5, 5 + J.seconds + 0.01)).toBe(0)
		t.expect(View.jumpRise(5, 0 / 0)).toBe(0)
		t.expect(View.jumpRise(0 / 0, 5)).toBe(0)
		t.expect(View.jumpRise(5, math.huge)).toBe(0)
	end)
end)
