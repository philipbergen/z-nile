--!strict
-- f0130 AC3: the camera position between two snapshots: a clamped lerp, except across a tunnel jump.
local Session = require("@logic/Session")
local View = require("@logic/View")
local t = require("@tests/lib/t")

local function snap(tick: number, x: number, y: number, jumpTick: number?): Session.Snapshot
	return {
		v = 1,
		tick = tick,
		maze = "classic",
		player = { x = x, y = y, heading = "E", moving = true, jumpTick = jumpTick or -1 },
	}
end

return t.spec("f0130 snapshot interpolation", function(it)
	local a = snap(10, 1, 2)
	local b = snap(11, 1.25, 2)

	it("interpolates linearly by alpha", function()
		t.expect(View.interpolate(a, b, 0)).toEqual({ x = 1, y = 2 })
		t.expect(View.interpolate(a, b, 0.5)).toEqual({ x = 1.125, y = 2 })
		t.expect(View.interpolate(a, b, 1)).toEqual({ x = 1.25, y = 2 })
		local v = View.interpolate(snap(10, 3, 4), snap(11, 3, 3.75), 0.25)
		t.expect(v.x).toBe(3)
		t.expect(v.y).toBeNear(3.9375, 1e-12)
	end)

	it("clamps alpha to 0..1 and treats NaN as 1", function()
		t.expect(View.interpolate(a, b, -3)).toEqual({ x = 1, y = 2 })
		t.expect(View.interpolate(a, b, 7)).toEqual({ x = 1.25, y = 2 })
		t.expect(View.interpolate(a, b, 0 / 0)).toEqual({ x = 1.25, y = 2 })
	end)

	it("shows the latest snapshot when there is no earlier one", function()
		t.expect(View.interpolate(nil, b, 0)).toEqual({ x = 1.25, y = 2 })
	end)

	it("does not slide across the maze after a tunnel jump between the two snapshots", function()
		local before = snap(11, 27.75, 14)
		local after = snap(12, 0, 14, 12)
		t.expect(View.interpolate(before, after, 0)).toEqual({ x = 0, y = 14 })
		t.expect(View.interpolate(before, after, 0.5)).toEqual({ x = 0, y = 14 })
		-- a jump at or before the earlier snapshot is already reflected in both
		local later = snap(13, 0.25, 14, 12)
		t.expect(View.interpolate(after, later, 0.5)).toEqual({ x = 0.125, y = 14 })
	end)

	it("interpolates across a gap of several ticks, and ignores an out-of-order earlier snapshot", function()
		t.expect(View.interpolate(snap(10, 1, 2), snap(13, 1.75, 2), 0.5)).toEqual({ x = 1.375, y = 2 })
		t.expect(View.interpolate(snap(14, 9, 9), b, 0.5)).toEqual({ x = 1.25, y = 2 })
		t.expect(View.interpolate(b, b, 0.5)).toEqual({ x = 1.25, y = 2 })
	end)
end)
