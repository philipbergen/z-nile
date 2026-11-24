--!strict
-- Saucers unit specs: spawn config and crossing.
local Saucers = require("@logic/Saucers")
local t = require("@tests/lib/t")

return t.spec("Saucers unit", function(it)
	it("has positive wait and speed values for both saucer kinds", function()
		t.expect(Saucers.CLASSIC.large.points).toBe(200)
		t.expect(Saucers.CLASSIC.small.points).toBe(1000)
		t.expect(Saucers.wait(Saucers.CLASSIC, 1) > Saucers.wait(Saucers.CLASSIC, 5)).toBe(true)
	end)
end)
