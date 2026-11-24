--!strict
-- Field unit specs: wrap, delta, distance, heading, and sweep.
local Field = require("@logic/Field")
local t = require("@tests/lib/t")

return t.spec("Field unit", function(it)
	it("wraps coordinates and computes shortest delta across boundaries", function()
		local f = Field.CLASSIC
		local wx, wy = Field.wrap(f, -10, f.height + 5)
		t.expect(wx).toBeNear(f.width - 10, 1e-6)
		t.expect(wy).toBeNear(5, 1e-6)
		local dx, dy = Field.delta(f, f.width - 10, 10, 10, 10)
		t.expect(dx).toBeNear(20, 1e-6)
		t.expect(dy).toBeNear(0, 1e-6)
	end)

	it("detects sweep hits and misses cleanly", function()
		local f = Field.CLASSIC
		local hit = Field.sweep(f, 0, 0, 100, 0, 50, 0, 10)
		t.expect(hit ~= nil).toBe(true)
		t.expect(hit :: number).toBeNear(0.4, 1e-6)
		t.expect(Field.sweep(f, 0, 0, 100, 0, 50, 20, 10)).toBe(nil)
	end)
end)
