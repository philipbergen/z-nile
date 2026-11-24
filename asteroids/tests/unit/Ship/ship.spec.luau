--!strict
-- Ship unit specs: turning, thrusting, drag, and top speed cap.
local Field = require("@logic/Field")
local Ship = require("@logic/Ship")
local t = require("@tests/lib/t")

return t.spec("Ship unit", function(it)
	it("starts at rest pointing up and caps speed under sustained thrust", function()
		local s = Ship.new(Ship.CLASSIC, 512, 384)
		t.expect(s.heading).toBe(Ship.CLASSIC.startHeading)
		t.expect(s.vx).toBe(0)
		t.expect(s.vy).toBe(0)
		for _ = 1, 200 do
			Ship.fly(s, Ship.CLASSIC, Field.CLASSIC, 0, true)
		end
		local speed = math.sqrt(s.vx * s.vx + s.vy * s.vy)
		t.expect(speed <= Ship.CLASSIC.maxSpeed + 1e-6).toBe(true)
		t.expect(speed > Ship.CLASSIC.maxSpeed * 0.9).toBe(true)
	end)
end)
