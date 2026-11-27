--!strict
-- Narrowed by c0182: dropped the right-half drag-look delta case and Touch.track drag call (replaced by d0149's look
-- circle in d0149/acceptance/fold.spec and look.spec). Keeps View.look's pitch clamp, yaw wrap and constants.
-- f0028 AC1: a look-zone move is a pixel delta, applied by View.look (pitch clamp, yaw wrap).
local View = require("@logic/View")
local t = require("@tests/lib/t")

local PI = math.pi

local function inRange(yaw: number): boolean
	return yaw > -PI and yaw <= PI
end

return t.spec("f0028 look deltas", function(it)
	it("a large look delta clamps pitch at MAX_PITCH and keeps yaw in (-pi, pi]", function()
		t.expect(View.look({ yaw = 0, pitch = 0 }, 0, 10000).pitch).toBe(-View.MAX_PITCH)
		t.expect(View.look({ yaw = 0, pitch = 0 }, 0, -10000).pitch).toBe(View.MAX_PITCH)
		local spun = View.look({ yaw = 0, pitch = 0 }, -100000, 0)
		t.expect(inRange(spun.yaw)).toBe(true)
		t.expect(View.MOUSE_RADIANS_PER_PIXEL).toBe(0.004)
		t.expect(View.MAX_PITCH > 0 and View.MAX_PITCH < PI / 2).toBe(true)
	end)
end)
