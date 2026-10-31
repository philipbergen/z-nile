--!strict
-- d0149 AC4: the look circle's point in View (decided with the user 2026-10-31: "Points the view"): it rides in the
-- arrows (View.Arrows.point), so View.arrowQuarters, View.steer and View.aim treat it as one more arrow, continuous:
-- the look turns toward it at the arrows' rate with the pitch level, aims by it, and springs back when it is let go.
-- Held arrows win over it. Without a point every arrow rule is as f0104 pinned it.
local View: any = require("@logic/View")
local t = require("@tests/lib/t")

local PI = math.pi
local NONE = { up = false, down = false, left = false, right = false }

local function arrows(point: number?, left: boolean?): any
	return { up = false, down = false, left = left == true, right = false, point = point }
end

return t.spec("d0149 the look circle's point", function(it)
	it("arrowQuarters is the point while no arrow is held, and nil without one", function()
		t.expect(View.arrowQuarters(arrows(0.5))).toBe(0.5)
		t.expect(View.arrowQuarters(arrows(2))).toBe(2)
		t.expect(View.arrowQuarters(arrows(nil))).toBe(nil)
		t.expect(View.arrowQuarters(NONE)).toBe(nil)
		t.expect(View.arrowQuarters(arrows(0 / 0))).toBe(nil)
		t.expect(View.arrowQuarters(arrows(math.huge))).toBe(nil)
	end)

	it("a held arrow wins over the point", function()
		t.expect(View.arrowQuarters(arrows(-1, true))).toBe(1)
	end)

	it(
		"the look turns toward the point at the arrows' rate, pitch level, and springs back when it goes",
		function()
			local s = { look = { yaw = 0, pitch = 0.3 }, spring = false }
			local dt = 0.01
			local step = View.turnRate() * dt
			s = View.steer(s, s.look, arrows(1), dt)
			t.expect(s.look.yaw).toBeNear(step, 1e-9)
			t.expect(s.look.pitch).toBeNear(0.3 - step, 1e-9)
			for _ = 1, 200 do
				s = View.steer(s, s.look, arrows(1), dt)
			end
			t.expect(s.look.yaw).toBeNear(PI / 2, 1e-9)
			t.expect(s.look.pitch).toBeNear(0, 1e-9)
			t.expect(s.spring).toBe(true)
			s = View.steer(s, s.look, arrows(nil), dt)
			t.expect(s.look.yaw).toBeNear(PI / 2 - step, 1e-9) -- let go: back toward the heading
			for _ = 1, 200 do
				s = View.steer(s, s.look, arrows(nil), dt)
			end
			t.expect(s.look.yaw).toBeNear(0, 1e-9)
			t.expect(s.spring).toBe(false)
		end
	)

	it(
		"a shot aims by the point, rounded to the nearest heading, and a tie goes the way of travel",
		function()
			local still = { look = { yaw = 0, pitch = 0 }, spring = false }
			t.expect(View.aim("N", still, arrows(1))).toBe("W")
			t.expect(View.aim("N", still, arrows(-0.6))).toBe("E")
			t.expect(View.aim("N", still, arrows(1.8))).toBe("S")
			t.expect(View.aim("N", still, arrows(0.5))).toBe("N") -- exactly half way: ahead
			t.expect(View.aim("N", still, arrows(1.5))).toBe("S") -- exactly half way behind: behind
			t.expect(View.aim("N", still, arrows(nil))).toBe("N")
		end
	)
end)
