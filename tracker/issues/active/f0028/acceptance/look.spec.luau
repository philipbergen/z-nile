--!strict
-- f0028 AC1: a look-zone move is a pixel delta, applied by View.look (pitch clamp, yaw wrap).
local Touch = require("@logic/Touch")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local PI = math.pi

local function inRange(yaw: number): boolean
	return yaw > -PI and yaw <= PI
end

return t.spec("f0028 look deltas", function(it)
	it("each move is the step from the previous point, not from the finger-down point", function()
		local state = Touch.empty()
		local effects
		state, effects = Touch.track(
			state,
			{ id = 1, phase = "begin", x = 500, y = 200 },
			{ width = 800, snap = nil }
		)
		t.expect(effects).toEqual({})
		local moved
		state, moved = Touch.track(
			state,
			{ id = 1, phase = "move", x = 530, y = 190 },
			{ width = 800, snap = nil }
		)
		t.expect(moved).toEqual({ { kind = "look", dx = 30, dy = -10 } })
		local again
		state, again = Touch.track(
			state,
			{ id = 1, phase = "move", x = 530, y = 190 },
			{ width = 800, snap = nil }
		)
		t.expect(again).toEqual({ { kind = "look", dx = 0, dy = 0 } })
		local _, second = Touch.track(
			state,
			{ id = 1, phase = "move", x = 530, y = 10190 },
			{ width = 800, snap = nil }
		)
		t.expect(second).toEqual({ { kind = "look", dx = 0, dy = 10000 } })
	end)

	it("a large look delta clamps pitch at MAX_PITCH and keeps yaw in (-pi, pi]", function()
		local state = Touch.empty()
		state = Touch.track(state, { id = 1, phase = "begin", x = 600, y = 100 }, { width = 800, snap = nil })
		local _, down = Touch.track(
			state,
			{ id = 1, phase = "move", x = 600, y = 10100 },
			{ width = 800, snap = nil }
		)
		local _, up = Touch.track(
			state,
			{ id = 1, phase = "move", x = 600, y = 100 - 10000 },
			{ width = 800, snap = nil }
		)
		t.expect(down[1].dy).toBe(10000)
		t.expect(up[1].dy).toBe(-10000)
		t.expect(View.look({ yaw = 0, pitch = 0 }, down[1].dx, down[1].dy).pitch).toBe(-View.MAX_PITCH)
		t.expect(View.look({ yaw = 0, pitch = 0 }, up[1].dx, up[1].dy).pitch).toBe(View.MAX_PITCH)
		local spun = View.look({ yaw = 0, pitch = 0 }, -100000, 0)
		t.expect(inRange(spun.yaw)).toBe(true)
		t.expect(View.MOUSE_RADIANS_PER_PIXEL).toBe(0.004)
		t.expect(View.MAX_PITCH > 0 and View.MAX_PITCH < PI / 2).toBe(true)
	end)
end)
