--!strict
-- Look unit specs: wrap, approach, ease, mouse/turn, arrow spring-back, and blending.
local Look = require("@logic/Look")
local t = require("@tests/lib/t")

return t.spec("Look unit", function(it)
	it("wraps angles to (-pi, pi] and blends the short way", function()
		t.expect(Look.wrap(-math.pi)).toBeNear(math.pi, 1e-6)
		t.expect(Look.blendYaw(math.rad(170), math.rad(-170), 0.5)).toBeNear(math.pi, 1e-6)
		t.expect(Look.alpha(0 / 0, 10)).toBe(1)
	end)

	it("springs back after arrow look and yields to other look input", function()
		local s = Look.rest()
		local a = Look.press(Look.arrows(), "left", true)
		s = Look.spring(s, s.look, a, 0.12)
		t.expect(s.look.yaw).toBeNear(math.pi / 2, 1e-6)
		t.expect(s.spring).toBe(true)

		local released = Look.press(a, "left", false)
		s = Look.spring(s, s.look, released, 0.06)
		t.expect(s.spring).toBe(true)
		-- another look input during spring takes over and ends the spring
		local moved = Look.turn(s.look, 0.2, 0)
		local taken = Look.spring(s, moved, released, 0.06)
		t.expect(taken.spring).toBe(false)
		t.expect(taken.look.yaw).toBeNear(moved.yaw, 1e-6)

		-- uninterrupted spring returns to rest
		s = Look.spring(s, s.look, released, 0.12)
		t.expect(s.look.yaw).toBeNear(0, 1e-6)
		t.expect(s.spring).toBe(false)
	end)

	it("refuses invalid tunings", function()
		t.expect(function()
			Look.tune({ maxPitch = math.pi })
		end).toThrow("Look.tune")
	end)
end)
