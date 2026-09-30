--!strict
-- f0130 AC4: camera yaw smoothing and free look.
local View = require("@logic/View")
local t = require("@tests/lib/t")

local PI = math.pi

local function inRange(a: number): boolean
	return a > -PI and a <= PI
end

return t.spec("f0130 turning and looking", function(it)
	it("approachYaw steps toward the target by at most maxDelta", function()
		t.expect(View.approachYaw(0, PI / 2, 0.1)).toBeNear(0.1, 1e-12)
		t.expect(View.approachYaw(0, -PI / 2, 0.1)).toBeNear(-0.1, 1e-12)
		t.expect(View.approachYaw(0.05, 0, 0.1)).toBe(0)
	end)

	it("approachYaw takes the shorter way around and stays in (-pi, pi]", function()
		local a = View.approachYaw(3.0, -3.0, 0.1) -- 0.28 rad apart across pi: go up
		t.expect(a).toBeNear(3.1, 1e-12)
		local b = View.approachYaw(3.1, -3.1, 0.2) -- reaches it, wrapping past pi
		t.expect(b).toBeNear(-3.1, 1e-12)
		t.expect(inRange(b)).toBe(true)
		t.expect(View.approachYaw(-PI / 2, PI, 0.1)).toBeNear(-PI / 2 - 0.1, 1e-12)
	end)

	it("a quarter turn at turnRate takes TURN_SECONDS, within one frame", function()
		t.expect(View.TURN_SECONDS > 0 and View.TURN_SECONDS <= 0.3).toBe(true)
		local dt = 1 / 60
		local yaw, frames = 0, 0
		while math.abs(yaw - PI / 2) > 1e-9 do
			yaw = View.approachYaw(yaw, PI / 2, View.turnRate() * dt)
			frames += 1
			t.expect(frames < 1000).toBe(true)
		end
		t.expect(math.abs(frames * dt - View.TURN_SECONDS) <= dt + 1e-9).toBe(true)
	end)

	it("the mouse turns the view: right and down are negative yaw and pitch", function()
		local l = View.look({ yaw = 0, pitch = 0 }, 10, 5)
		t.expect(l.yaw < 0).toBe(true)
		t.expect(l.pitch < 0).toBe(true)
		t.expect(l.yaw).toBeNear(-10 * View.MOUSE_RADIANS_PER_PIXEL, 1e-12)
		t.expect(l.pitch).toBeNear(-5 * View.MOUSE_RADIANS_PER_PIXEL, 1e-12)
	end)

	it("pitch is clamped to MAX_PITCH, which stays short of straight up or down", function()
		t.expect(View.MAX_PITCH > 0 and View.MAX_PITCH < PI / 2).toBe(true)
		t.expect(View.look({ yaw = 0, pitch = 0 }, 0, 1e6).pitch).toBe(-View.MAX_PITCH)
		t.expect(View.look({ yaw = 0, pitch = 0 }, 0, -1e6).pitch).toBe(View.MAX_PITCH)
	end)

	it("look yaw is unlimited but kept in (-pi, pi]", function()
		local l = { yaw = 0, pitch = 0 }
		for _ = 1, 50 do
			l = View.look(l, -500, 0)
			t.expect(inRange(l.yaw)).toBe(true)
		end
	end)

	it("snap recentres the look on the heading", function()
		t.expect(View.snap({ yaw = 2, pitch = -1 })).toEqual({ yaw = 0, pitch = 0 })
	end)
end)
